#include "iphone_arkit_head_tracker.h"

#if VERSION_MAJOR == 4
#include "core/object/class_db.h"
#else
#include "core/class_db.h"
#endif

#import <ARKit/ARKit.h>
#import <Foundation/Foundation.h>
#import <simd/simd.h>

IPhoneARKitHeadTracker *IPhoneARKitHeadTracker::instance = nullptr;

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
	ClassDB::bind_method(D_METHOD("reset_tracking_reference"), &IPhoneARKitHeadTracker::reset_tracking_reference);
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

void IPhoneARKitHeadTracker::reset_tracking_reference() {
	if (session) {
		[session resetTrackingReference];
	}
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

IPhoneARKitHeadTracker::IPhoneARKitHeadTracker() {
	ERR_FAIL_COND(instance != nullptr);
	instance = this;

	latest_position_meters = Vector3(0.0, 0.0, 0.35);
	tracking_supported = false;
	tracking_started = false;
	face_tracked = false;
	status_message = "created";
	frame_count = 0;

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
