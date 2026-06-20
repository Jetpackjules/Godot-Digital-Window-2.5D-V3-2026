#include "iphone_arkit_head_tracker.h"

#if VERSION_MAJOR == 4
#include "core/object/class_db.h"
#include "core/math/color.h"
#include "core/variant/array.h"
#include "core/variant/packed_color_array.h"
#include "core/variant/packed_float32_array.h"
#else
#include "core/class_db.h"
#endif

#import <ARKit/ARKit.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <simd/simd.h>

IPhoneARKitHeadTracker *IPhoneARKitHeadTracker::instance = nullptr;

static double _clamp_unit(double value) {
	if (value < 0.0) {
		return 0.0;
	}
	if (value > 1.0) {
		return 1.0;
	}
	return value;
}

static size_t _clamp_index(size_t value, size_t upper_bound) {
	if (upper_bound == 0) {
		return 0;
	}
	return value < upper_bound ? value : upper_bound - 1;
}

static Color _color_from_ycbcr(double y, double cb, double cr) {
	double r = y + 1.402 * (cr - 0.5);
	double g = y - 0.344136 * (cb - 0.5) - 0.714136 * (cr - 0.5);
	double b = y + 1.772 * (cb - 0.5);
	return Color(_clamp_unit(r), _clamp_unit(g), _clamp_unit(b), 1.0);
}

static Dictionary _sample_camera_light_grid(ARFrame *frame) {
	Dictionary estimate;
	estimate["active"] = false;
	if (frame == nil) {
		return estimate;
	}

	CVPixelBufferRef pixel_buffer = frame.capturedImage;
	if (pixel_buffer == nil) {
		return estimate;
	}

	const int grid_width = 3;
	const int grid_height = 3;
	const int grid_count = grid_width * grid_height;
	double luma_sums[grid_count] = {0.0};
	double red_sums[grid_count] = {0.0};
	double green_sums[grid_count] = {0.0};
	double blue_sums[grid_count] = {0.0};
	int sample_counts[grid_count] = {0};
	double total_luma = 0.0;
	double total_red = 0.0;
	double total_green = 0.0;
	double total_blue = 0.0;
	int total_samples = 0;

	CVPixelBufferLockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);
	OSType pixel_format = CVPixelBufferGetPixelFormatType(pixel_buffer);
	size_t width = CVPixelBufferGetWidth(pixel_buffer);
	size_t height = CVPixelBufferGetHeight(pixel_buffer);

	if ((pixel_format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || pixel_format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) && CVPixelBufferGetPlaneCount(pixel_buffer) >= 2) {
		uint8_t *y_plane = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixel_buffer, 0);
		uint8_t *cbcr_plane = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixel_buffer, 1);
		size_t y_stride = CVPixelBufferGetBytesPerRowOfPlane(pixel_buffer, 0);
		size_t cbcr_stride = CVPixelBufferGetBytesPerRowOfPlane(pixel_buffer, 1);
		for (int gy = 0; gy < grid_height; gy++) {
			for (int gx = 0; gx < grid_width; gx++) {
				int cell_index = gy * grid_width + gx;
				for (int sy = 0; sy < 6; sy++) {
					for (int sx = 0; sx < 6; sx++) {
						size_t px = (size_t)(((double)gx + ((double)sx + 0.5) / 6.0) * (double)width / (double)grid_width);
						size_t py = (size_t)(((double)gy + ((double)sy + 0.5) / 6.0) * (double)height / (double)grid_height);
						px = _clamp_index(px, width);
						py = _clamp_index(py, height);
						double y = (double)y_plane[py * y_stride + px] / 255.0;
						size_t cpx = _clamp_index(px / 2, CVPixelBufferGetWidthOfPlane(pixel_buffer, 1));
						size_t cpy = _clamp_index(py / 2, CVPixelBufferGetHeightOfPlane(pixel_buffer, 1));
						uint8_t *cbcr = cbcr_plane + cpy * cbcr_stride + cpx * 2;
						Color color = _color_from_ycbcr(y, (double)cbcr[0] / 255.0, (double)cbcr[1] / 255.0);
						luma_sums[cell_index] += y;
						red_sums[cell_index] += color.r;
						green_sums[cell_index] += color.g;
						blue_sums[cell_index] += color.b;
						sample_counts[cell_index]++;
						total_luma += y;
						total_red += color.r;
						total_green += color.g;
						total_blue += color.b;
						total_samples++;
					}
				}
			}
		}
	} else if (pixel_format == kCVPixelFormatType_32BGRA) {
		uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddress(pixel_buffer);
		size_t stride = CVPixelBufferGetBytesPerRow(pixel_buffer);
		for (int gy = 0; gy < grid_height; gy++) {
			for (int gx = 0; gx < grid_width; gx++) {
				int cell_index = gy * grid_width + gx;
				for (int sy = 0; sy < 6; sy++) {
					for (int sx = 0; sx < 6; sx++) {
						size_t px = (size_t)(((double)gx + ((double)sx + 0.5) / 6.0) * (double)width / (double)grid_width);
						size_t py = (size_t)(((double)gy + ((double)sy + 0.5) / 6.0) * (double)height / (double)grid_height);
						px = _clamp_index(px, width);
						py = _clamp_index(py, height);
						uint8_t *pixel = base + py * stride + px * 4;
						double b = (double)pixel[0] / 255.0;
						double g = (double)pixel[1] / 255.0;
						double r = (double)pixel[2] / 255.0;
						double y = r * 0.2126 + g * 0.7152 + b * 0.0722;
						luma_sums[cell_index] += y;
						red_sums[cell_index] += r;
						green_sums[cell_index] += g;
						blue_sums[cell_index] += b;
						sample_counts[cell_index]++;
						total_luma += y;
						total_red += r;
						total_green += g;
						total_blue += b;
						total_samples++;
					}
				}
			}
		}
	}
	CVPixelBufferUnlockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);

	if (total_samples <= 0) {
		return estimate;
	}

	PackedFloat32Array grid_luma;
	PackedColorArray grid_colors;
	int brightest_index = 0;
	double brightest_luma = -1.0;
	for (int i = 0; i < grid_count; i++) {
		double divisor = sample_counts[i] > 0 ? sample_counts[i] : 1;
		double luma = luma_sums[i] / divisor;
		if (luma > brightest_luma) {
			brightest_luma = luma;
			brightest_index = i;
		}
		grid_luma.push_back((float)luma);
		grid_colors.push_back(Color(red_sums[i] / divisor, green_sums[i] / divisor, blue_sums[i] / divisor, 1.0));
	}

	ARLightEstimate *light_estimate = frame.lightEstimate;
	estimate["active"] = true;
	estimate["grid_width"] = grid_width;
	estimate["grid_height"] = grid_height;
	estimate["grid_luma"] = grid_luma;
	estimate["grid_colors"] = grid_colors;
	estimate["average_luma"] = total_luma / (double)total_samples;
	estimate["average_color"] = Color(total_red / (double)total_samples, total_green / (double)total_samples, total_blue / (double)total_samples, 1.0);
	estimate["brightest_index"] = brightest_index;
	estimate["brightest_luma"] = brightest_luma;
	estimate["ambient_intensity"] = light_estimate ? light_estimate.ambientIntensity : 1000.0;
	estimate["ambient_color_temperature"] = light_estimate ? light_estimate.ambientColorTemperature : 6500.0;
	return estimate;
}

@interface IPhoneARKitHeadTrackerSession : NSObject <ARSessionDelegate>

@property(nonatomic, assign) IPhoneARKitHeadTracker *owner;
@property(nonatomic, strong) ARSession *arSession;
@property(nonatomic, assign) BOOL started;
@property(nonatomic, assign) BOOL supported;
@property(nonatomic, assign) BOOL tracked;

- (instancetype)initWithOwner:(IPhoneARKitHeadTracker *)owner;
- (Error)startTracking;
- (void)stopTracking;
- (void)resetTrackingReference;

@end

@implementation IPhoneARKitHeadTrackerSession

- (instancetype)initWithOwner:(IPhoneARKitHeadTracker *)owner {
	self = [super init];
	if (self) {
		_owner = owner;
		_arSession = [[ARSession alloc] init];
		_arSession.delegate = self;
		_started = NO;
		_tracked = NO;
		_supported = [ARFaceTrackingConfiguration isSupported];
	}
	return self;
}

- (Error)startTracking {
	if (!_supported) {
		if (_owner) {
			_owner->update_support_state(false, "ARFaceTrackingConfiguration is not supported on this device.");
		}
		return ERR_UNAVAILABLE;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		ARFaceTrackingConfiguration *configuration = [[ARFaceTrackingConfiguration alloc] init];
		configuration.lightEstimationEnabled = NO;

		[self.arSession runWithConfiguration:configuration options:ARSessionRunOptionResetTracking | ARSessionRunOptionRemoveExistingAnchors];
		self.started = YES;
		if (self.owner) {
			self.owner->update_support_state(true, "tracking-started");
		}
	});

	return OK;
}

- (void)stopTracking {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.arSession pause];
		self.started = NO;
		self.tracked = NO;
		if (self.owner) {
			self.owner->update_head_position(Vector3(0.0, 0.0, 0.35), false);
			self.owner->update_support_state(self.supported, "tracking-stopped");
		}
	});
}

- (void)resetTrackingReference {
	if (!_started || !_supported) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		ARFaceTrackingConfiguration *configuration = [[ARFaceTrackingConfiguration alloc] init];
		configuration.lightEstimationEnabled = NO;
		[self.arSession runWithConfiguration:configuration options:ARSessionRunOptionResetTracking | ARSessionRunOptionRemoveExistingAnchors];
	});
}

- (void)session:(ARSession *)session didUpdateAnchors:(NSArray<ARAnchor *> *)anchors {
	ARFrame *frame = session.currentFrame;
	if (frame == nil) {
		return;
	}
	if (self.owner && self.owner->should_sample_camera_light_estimate()) {
		self.owner->update_camera_light_estimate(_sample_camera_light_grid(frame));
	}

	matrix_float4x4 cameraFromWorld = simd_inverse(frame.camera.transform);

	for (ARAnchor *anchor in anchors) {
		if (![anchor isKindOfClass:[ARFaceAnchor class]]) {
			continue;
		}

		ARFaceAnchor *faceAnchor = (ARFaceAnchor *)anchor;
		matrix_float4x4 cameraFromFace = simd_mul(cameraFromWorld, faceAnchor.transform);
		vector_float4 translation = cameraFromFace.columns[3];

		// ARKit camera space looks along -Z. The Godot screen-local contract uses
		// +Z out from the glass toward the viewer.
		Vector3 screenLocalMeters(translation.x, translation.y, -translation.z);
		self.tracked = faceAnchor.isTracked;

		if (self.owner) {
			self.owner->update_head_position(screenLocalMeters, self.tracked);
			self.owner->update_support_state(self.supported, self.tracked ? "face-tracked" : "face-visible-but-not-tracked");
		}
	}
}

- (void)session:(ARSession *)session didFailWithError:(NSError *)error {
	self.tracked = NO;
	if (self.owner) {
		NSString *message = error.localizedDescription ?: @"ARSession failed.";
		self.owner->update_support_state(self.supported, String::utf8(message.UTF8String));
		self.owner->update_head_position(Vector3(0.0, 0.0, 0.35), false);
	}
}

- (void)sessionWasInterrupted:(ARSession *)session {
	self.tracked = NO;
	if (self.owner) {
		self.owner->update_support_state(self.supported, "session-interrupted");
		self.owner->update_head_position(Vector3(0.0, 0.0, 0.35), false);
	}
}

- (void)sessionInterruptionEnded:(ARSession *)session {
	if (self.owner) {
		self.owner->update_support_state(self.supported, "session-interruption-ended");
	}
	[self resetTrackingReference];
}

@end

void IPhoneARKitHeadTracker::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start_tracking"), &IPhoneARKitHeadTracker::start_tracking);
	ClassDB::bind_method(D_METHOD("stop_tracking"), &IPhoneARKitHeadTracker::stop_tracking);
	ClassDB::bind_method(D_METHOD("is_tracking"), &IPhoneARKitHeadTracker::is_tracking);
	ClassDB::bind_method(D_METHOD("get_screen_local_head_position_meters"), &IPhoneARKitHeadTracker::get_screen_local_head_position_meters);
	ClassDB::bind_method(D_METHOD("get_tracking_status"), &IPhoneARKitHeadTracker::get_tracking_status);
	ClassDB::bind_method(D_METHOD("get_camera_light_estimate"), &IPhoneARKitHeadTracker::get_camera_light_estimate);
	ClassDB::bind_method(D_METHOD("set_camera_light_estimation_enabled", "enabled"), &IPhoneARKitHeadTracker::set_camera_light_estimation_enabled);
	ClassDB::bind_method(D_METHOD("is_camera_light_estimation_enabled"), &IPhoneARKitHeadTracker::is_camera_light_estimation_enabled);
	ClassDB::bind_method(D_METHOD("reset_tracking_reference"), &IPhoneARKitHeadTracker::reset_tracking_reference);
	ClassDB::bind_method(D_METHOD("play_haptic_impact", "intensity"), &IPhoneARKitHeadTracker::play_haptic_impact);
	ClassDB::bind_method(D_METHOD("play_haptic_selection"), &IPhoneARKitHeadTracker::play_haptic_selection);
}

IPhoneARKitHeadTracker *IPhoneARKitHeadTracker::get_singleton() {
	return instance;
}

Error IPhoneARKitHeadTracker::start_tracking() {
	if (!session) {
		return ERR_UNAVAILABLE;
	}
	return [session startTracking];
}

void IPhoneARKitHeadTracker::stop_tracking() {
	if (session) {
		[session stopTracking];
	}
	tracking_started = false;
	face_tracked = false;
}

bool IPhoneARKitHeadTracker::is_tracking() const {
	return tracking_started && face_tracked;
}

Vector3 IPhoneARKitHeadTracker::get_screen_local_head_position_meters() const {
	return latest_position_meters;
}

Dictionary IPhoneARKitHeadTracker::get_tracking_status() const {
	Dictionary status;
	status["source"] = "arkit";
	status["supported"] = tracking_supported;
	status["started"] = tracking_started;
	status["active"] = is_tracking();
	status["face_tracked"] = face_tracked;
	status["frame_count"] = frame_count;
	status["message"] = status_message;
	status["position_m"] = latest_position_meters;
	return status;
}

Dictionary IPhoneARKitHeadTracker::get_camera_light_estimate() const {
	return latest_camera_light_estimate;
}

void IPhoneARKitHeadTracker::set_camera_light_estimation_enabled(bool enabled) {
	camera_light_estimation_enabled = enabled;
	if (!enabled) {
		latest_camera_light_estimate.clear();
		latest_camera_light_estimate["active"] = false;
	}
}

bool IPhoneARKitHeadTracker::is_camera_light_estimation_enabled() const {
	return camera_light_estimation_enabled;
}

void IPhoneARKitHeadTracker::reset_tracking_reference() {
	if (session) {
		[session resetTrackingReference];
	}
}

void IPhoneARKitHeadTracker::play_haptic_impact(double intensity) {
	double clamped_intensity = intensity;
	if (clamped_intensity < 0.0) {
		clamped_intensity = 0.0;
	}
	if (clamped_intensity > 1.0) {
		clamped_intensity = 1.0;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		UIImpactFeedbackGeneratorStyle style = UIImpactFeedbackStyleMedium;
		if (clamped_intensity < 0.28) {
			style = UIImpactFeedbackStyleLight;
		} else if (clamped_intensity > 0.72) {
			style = UIImpactFeedbackStyleHeavy;
		}

		UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
		[generator prepare];
		if (@available(iOS 13.0, *)) {
			[generator impactOccurredWithIntensity:(CGFloat)clamped_intensity];
		} else {
			[generator impactOccurred];
		}
	});
}

void IPhoneARKitHeadTracker::play_haptic_selection() {
	dispatch_async(dispatch_get_main_queue(), ^{
		UISelectionFeedbackGenerator *generator = [[UISelectionFeedbackGenerator alloc] init];
		[generator prepare];
		[generator selectionChanged];
	});
}

void IPhoneARKitHeadTracker::update_head_position(const Vector3 &position_meters, bool tracked) {
	latest_position_meters = position_meters;
	face_tracked = tracked;
	tracking_started = session != nullptr && [session started];
	frame_count++;
}

void IPhoneARKitHeadTracker::update_support_state(bool supported, const String &message) {
	tracking_supported = supported;
	status_message = message;
	if (session) {
		tracking_started = [session started];
	}
}

bool IPhoneARKitHeadTracker::should_sample_camera_light_estimate() const {
	return camera_light_estimation_enabled;
}

void IPhoneARKitHeadTracker::update_camera_light_estimate(const Dictionary &estimate) {
	latest_camera_light_estimate = estimate;
}

IPhoneARKitHeadTracker::IPhoneARKitHeadTracker() {
	ERR_FAIL_COND(instance != nullptr);
	instance = this;

	latest_position_meters = Vector3(0.0, 0.0, 0.35);
	tracking_supported = false;
	tracking_started = false;
	face_tracked = false;
	camera_light_estimation_enabled = false;
	status_message = "created";
	frame_count = 0;
	latest_camera_light_estimate["active"] = false;

	session = [[IPhoneARKitHeadTrackerSession alloc] initWithOwner:this];
	tracking_supported = [session supported];
	status_message = tracking_supported ? "ready" : "face-tracking-unsupported";
}

IPhoneARKitHeadTracker::~IPhoneARKitHeadTracker() {
	if (session) {
		[session stopTracking];
		session = nil;
	}
	instance = nullptr;
}
