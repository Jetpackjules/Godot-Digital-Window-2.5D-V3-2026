#include "realsense_direct_frame_source.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>

using namespace godot;

RealSenseDirectFrameSource::RealSenseDirectFrameSource()
#ifdef REALSENSE_DIRECT_ENABLED
    : align_to_depth(RS2_STREAM_DEPTH),
      depth_to_disparity_filter(true),
      disparity_to_depth_filter(false)
#endif
{
}

RealSenseDirectFrameSource::~RealSenseDirectFrameSource() {
    close();
}

void RealSenseDirectFrameSource::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_stream_profile", "profile"), &RealSenseDirectFrameSource::set_stream_profile);
    ClassDB::bind_method(D_METHOD("get_stream_profile"), &RealSenseDirectFrameSource::get_stream_profile);
    ClassDB::bind_method(D_METHOD("set_stride", "stride"), &RealSenseDirectFrameSource::set_stride);
    ClassDB::bind_method(D_METHOD("get_stride"), &RealSenseDirectFrameSource::get_stride);
    ClassDB::bind_method(D_METHOD("set_color_output_enabled", "enabled"), &RealSenseDirectFrameSource::set_color_output_enabled);
    ClassDB::bind_method(D_METHOD("get_color_output_enabled"), &RealSenseDirectFrameSource::get_color_output_enabled);
    ClassDB::bind_method(D_METHOD("set_post_processing_enabled", "enabled"), &RealSenseDirectFrameSource::set_post_processing_enabled);
    ClassDB::bind_method(D_METHOD("set_decimation_filter_enabled", "enabled"), &RealSenseDirectFrameSource::set_decimation_filter_enabled);
    ClassDB::bind_method(D_METHOD("set_decimation_magnitude", "magnitude"), &RealSenseDirectFrameSource::set_decimation_magnitude);
    ClassDB::bind_method(D_METHOD("set_rotation_filter_enabled", "enabled"), &RealSenseDirectFrameSource::set_rotation_filter_enabled);
    ClassDB::bind_method(D_METHOD("set_hdr_merge_filter_enabled", "enabled"), &RealSenseDirectFrameSource::set_hdr_merge_filter_enabled);
    ClassDB::bind_method(D_METHOD("set_sequence_id_filter_enabled", "enabled"), &RealSenseDirectFrameSource::set_sequence_id_filter_enabled);
    ClassDB::bind_method(D_METHOD("set_threshold_filter_enabled", "enabled"), &RealSenseDirectFrameSource::set_threshold_filter_enabled);
    ClassDB::bind_method(D_METHOD("set_depth_to_disparity_filter_enabled", "enabled"), &RealSenseDirectFrameSource::set_depth_to_disparity_filter_enabled);
    ClassDB::bind_method(D_METHOD("set_spatial_filter_enabled", "enabled"), &RealSenseDirectFrameSource::set_spatial_filter_enabled);
    ClassDB::bind_method(D_METHOD("set_temporal_filter_enabled", "enabled"), &RealSenseDirectFrameSource::set_temporal_filter_enabled);
    ClassDB::bind_method(D_METHOD("set_hole_filling_filter_enabled", "enabled"), &RealSenseDirectFrameSource::set_hole_filling_filter_enabled);
    ClassDB::bind_method(D_METHOD("set_disparity_to_depth_filter_enabled", "enabled"), &RealSenseDirectFrameSource::set_disparity_to_depth_filter_enabled);
    ClassDB::bind_method(D_METHOD("set_filter_depth_range", "min_depth", "max_depth"), &RealSenseDirectFrameSource::set_filter_depth_range);
    ClassDB::bind_method(D_METHOD("set_hole_filling_mode", "mode"), &RealSenseDirectFrameSource::set_hole_filling_mode);
    ClassDB::bind_method(D_METHOD("open"), &RealSenseDirectFrameSource::open);
    ClassDB::bind_method(D_METHOD("close"), &RealSenseDirectFrameSource::close);
    ClassDB::bind_method(D_METHOD("is_open"), &RealSenseDirectFrameSource::is_open);
    ClassDB::bind_method(D_METHOD("poll"), &RealSenseDirectFrameSource::poll);
    ClassDB::bind_method(D_METHOD("get_sequence"), &RealSenseDirectFrameSource::get_sequence);
    ClassDB::bind_method(D_METHOD("get_frame_id"), &RealSenseDirectFrameSource::get_frame_id);
    ClassDB::bind_method(D_METHOD("get_capture_fps"), &RealSenseDirectFrameSource::get_capture_fps);
    ClassDB::bind_method(D_METHOD("get_width"), &RealSenseDirectFrameSource::get_width);
    ClassDB::bind_method(D_METHOD("get_height"), &RealSenseDirectFrameSource::get_height);
    ClassDB::bind_method(D_METHOD("get_source_width"), &RealSenseDirectFrameSource::get_source_width);
    ClassDB::bind_method(D_METHOD("get_source_height"), &RealSenseDirectFrameSource::get_source_height);
    ClassDB::bind_method(D_METHOD("get_intrinsics"), &RealSenseDirectFrameSource::get_intrinsics);
    ClassDB::bind_method(D_METHOD("get_depth_image"), &RealSenseDirectFrameSource::get_depth_image);
    ClassDB::bind_method(D_METHOD("get_color_image"), &RealSenseDirectFrameSource::get_color_image);
    ClassDB::bind_method(D_METHOD("get_status"), &RealSenseDirectFrameSource::get_status);
    ClassDB::bind_method(D_METHOD("get_filter_status"), &RealSenseDirectFrameSource::get_filter_status);

    ADD_PROPERTY(PropertyInfo(Variant::STRING, "stream_profile"), "set_stream_profile", "get_stream_profile");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "stride"), "set_stride", "get_stride");
}

RealSenseDirectFrameSource::StreamSettings RealSenseDirectFrameSource::resolve_stream_settings() const {
    const String profile = stream_profile.to_lower();
    StreamSettings settings;
    if (profile == "fast60") {
        settings.depth_width = 640;
        settings.depth_height = 480;
        settings.depth_fps = 60;
        settings.color_width = 640;
        settings.color_height = 480;
        settings.color_fps = 60;
    } else if (profile == "highres30") {
        settings.depth_width = 1280;
        settings.depth_height = 720;
        settings.depth_fps = 30;
        settings.color_width = 1280;
        settings.color_height = 720;
        settings.color_fps = 30;
    } else {
        settings.depth_width = 848;
        settings.depth_height = 480;
        settings.depth_fps = 30;
        settings.color_width = 1280;
        settings.color_height = 720;
        settings.color_fps = 30;
    }
    return settings;
}

void RealSenseDirectFrameSource::set_stream_profile(const String &p_profile) {
    String next = p_profile.to_lower();
    if (next != "fast60" && next != "viewer30" && next != "highres30") {
        next = "viewer30";
    }
    if (stream_profile == next) {
        return;
    }
    stream_profile = next;
    if (opened) {
        close();
        open();
    }
}

String RealSenseDirectFrameSource::get_stream_profile() const {
    return stream_profile;
}

void RealSenseDirectFrameSource::set_stride(int p_stride) {
    const int next = std::max(1, p_stride);
    if (stride == next) {
        return;
    }
    stride = next;
}

int RealSenseDirectFrameSource::get_stride() const {
    return stride;
}

void RealSenseDirectFrameSource::set_color_output_enabled(bool p_enabled) {
    color_output_enabled = p_enabled;
    if (!color_output_enabled) {
        color_image.unref();
    }
}

bool RealSenseDirectFrameSource::get_color_output_enabled() const {
    return color_output_enabled;
}

void RealSenseDirectFrameSource::set_post_processing_enabled(bool p_enabled) { post_processing_enabled = p_enabled; }
void RealSenseDirectFrameSource::set_decimation_filter_enabled(bool p_enabled) { decimation_filter_enabled = p_enabled; }
void RealSenseDirectFrameSource::set_decimation_magnitude(int p_magnitude) { decimation_magnitude = std::max(2, std::min(8, p_magnitude)); }
void RealSenseDirectFrameSource::set_rotation_filter_enabled(bool p_enabled) { rotation_filter_enabled = p_enabled; }
void RealSenseDirectFrameSource::set_hdr_merge_filter_enabled(bool p_enabled) { hdr_merge_filter_enabled = p_enabled; }
void RealSenseDirectFrameSource::set_sequence_id_filter_enabled(bool p_enabled) { sequence_id_filter_enabled = p_enabled; }
void RealSenseDirectFrameSource::set_threshold_filter_enabled(bool p_enabled) { threshold_filter_enabled = p_enabled; }
void RealSenseDirectFrameSource::set_depth_to_disparity_filter_enabled(bool p_enabled) { depth_to_disparity_filter_enabled = p_enabled; }
void RealSenseDirectFrameSource::set_spatial_filter_enabled(bool p_enabled) { spatial_filter_enabled = p_enabled; }
void RealSenseDirectFrameSource::set_temporal_filter_enabled(bool p_enabled) { temporal_filter_enabled = p_enabled; }
void RealSenseDirectFrameSource::set_hole_filling_filter_enabled(bool p_enabled) { hole_filling_filter_enabled = p_enabled; }
void RealSenseDirectFrameSource::set_disparity_to_depth_filter_enabled(bool p_enabled) { disparity_to_depth_filter_enabled = p_enabled; }

void RealSenseDirectFrameSource::set_filter_depth_range(float p_min_depth, float p_max_depth) {
    filter_min_depth = std::max(0.0f, p_min_depth);
    filter_max_depth = std::max(filter_min_depth + 0.01f, p_max_depth);
}

void RealSenseDirectFrameSource::set_hole_filling_mode(int p_mode) {
    hole_filling_mode = std::max(0, std::min(2, p_mode));
}

void RealSenseDirectFrameSource::reset_post_processing_filters() {
#ifdef REALSENSE_DIRECT_ENABLED
    decimation_filter = rs2::decimation_filter();
    rotation_filter = rs2::rotation_filter();
    hdr_merge_filter = rs2::hdr_merge();
    sequence_id_filter = rs2::sequence_id_filter();
    threshold_filter = rs2::threshold_filter();
    depth_to_disparity_filter = rs2::disparity_transform(true);
    spatial_filter = rs2::spatial_filter();
    temporal_filter = rs2::temporal_filter();
    hole_filling_filter = rs2::hole_filling_filter();
    disparity_to_depth_filter = rs2::disparity_transform(false);
#endif
}

void RealSenseDirectFrameSource::clear_frame() {
    sequence = 0;
    frame_id = 0;
    capture_fps = 0.0;
    capture_fps_frames = 0;
    capture_fps_window_start = 0.0;
    width = 0;
    height = 0;
    source_width = 0;
    source_height = 0;
    intrinsics = Vector4();
    depth_image.unref();
    color_image.unref();
    filter_status = "filters=off";
    valid_depth_pixels = 0;
}

#ifdef REALSENSE_DIRECT_ENABLED
bool RealSenseDirectFrameSource::open() {
    if (opened) {
        return true;
    }
    clear_frame();
    try {
        reset_post_processing_filters();
        const StreamSettings settings = resolve_stream_settings();
        rs2::config config;
        config.enable_stream(RS2_STREAM_DEPTH, settings.depth_width, settings.depth_height, RS2_FORMAT_Z16, settings.depth_fps);
        config.enable_stream(RS2_STREAM_COLOR, settings.color_width, settings.color_height, RS2_FORMAT_BGR8, settings.color_fps);
        pipeline_profile = pipeline.start(config);
        rs2::device device = pipeline_profile.get_device();
        rs2::depth_sensor depth_sensor = device.first<rs2::depth_sensor>();
        depth_scale = depth_sensor.get_depth_scale();
        opened = true;
        status = String("RealSense direct capture active: ") + stream_profile;
        UtilityFunctions::print(status);
        return true;
    } catch (const rs2::error &e) {
        opened = false;
        status = String("RealSense direct capture failed: ") + e.what();
        UtilityFunctions::push_warning(status);
        return false;
    } catch (const std::exception &e) {
        opened = false;
        status = String("RealSense direct capture failed: ") + e.what();
        UtilityFunctions::push_warning(status);
        return false;
    }
}

void RealSenseDirectFrameSource::close() {
    if (!opened) {
        return;
    }
    try {
        pipeline.stop();
    } catch (...) {
    }
    opened = false;
    clear_frame();
    status = "RealSense direct capture is closed";
    UtilityFunctions::print(status);
}

bool RealSenseDirectFrameSource::poll() {
    if (!opened) {
        return false;
    }
    try {
        rs2::frameset frames;
        if (!pipeline.poll_for_frames(&frames)) {
            return false;
        }
        frames = align_to_depth.process(frames);
        rs2::depth_frame depth_frame = frames.get_depth_frame();
        rs2::video_frame color_frame = frames.get_color_frame();
        if (!depth_frame || !color_frame) {
            return false;
        }

        if (post_processing_enabled) {
            auto set_filter_option = [](auto &p_filter, rs2_option p_option, float p_value) {
                if (p_filter.supports(p_option)) {
                    p_filter.set_option(p_option, p_value);
                }
            };
            auto append_filter_status = [](String &p_status, const char *p_name) {
                if (!p_status.ends_with(": ")) {
                    p_status += ",";
                }
                p_status += p_name;
            };
            auto append_skip_status = [](String &p_status, const char *p_name) {
                p_status += " skip:";
                p_status += p_name;
            };
            auto process_filter = [&append_filter_status, &append_skip_status](auto &p_filter, const char *p_name, rs2::frame &p_frame, String &p_status) {
                try {
                    rs2::frame next_frame = p_filter.process(p_frame);
                    if (next_frame) {
                        p_frame = next_frame;
                        append_filter_status(p_status, p_name);
                    } else {
                        append_skip_status(p_status, p_name);
                    }
                } catch (const rs2::error &) {
                    append_skip_status(p_status, p_name);
                } catch (const std::exception &) {
                    append_skip_status(p_status, p_name);
                }
            };

            rs2::frame filtered_depth = depth_frame;
            String next_filter_status = "filters=on: ";
            if (decimation_filter_enabled) {
                set_filter_option(decimation_filter, RS2_OPTION_FILTER_MAGNITUDE, float(decimation_magnitude));
                process_filter(decimation_filter, "decimation", filtered_depth, next_filter_status);
            }
            if (rotation_filter_enabled) {
                set_filter_option(rotation_filter, RS2_OPTION_ROTATION, 0.0f);
                process_filter(rotation_filter, "rotation", filtered_depth, next_filter_status);
            }
            if (hdr_merge_filter_enabled) {
                const bool has_hdr_sequence = filtered_depth.supports_frame_metadata(RS2_FRAME_METADATA_SEQUENCE_ID)
                    && filtered_depth.supports_frame_metadata(RS2_FRAME_METADATA_SEQUENCE_SIZE)
                    && filtered_depth.get_frame_metadata(RS2_FRAME_METADATA_SEQUENCE_SIZE) > 1;
                if (has_hdr_sequence) {
                    process_filter(hdr_merge_filter, "hdr", filtered_depth, next_filter_status);
                } else {
                    append_skip_status(next_filter_status, "hdr");
                }
            }
            if (sequence_id_filter_enabled) {
                const bool has_hdr_sequence = filtered_depth.supports_frame_metadata(RS2_FRAME_METADATA_SEQUENCE_ID)
                    && filtered_depth.supports_frame_metadata(RS2_FRAME_METADATA_SEQUENCE_SIZE)
                    && filtered_depth.get_frame_metadata(RS2_FRAME_METADATA_SEQUENCE_SIZE) > 1;
                if (has_hdr_sequence) {
                    set_filter_option(sequence_id_filter, RS2_OPTION_SEQUENCE_ID, 1.0f);
                    process_filter(sequence_id_filter, "sequence", filtered_depth, next_filter_status);
                } else {
                    append_skip_status(next_filter_status, "sequence");
                }
            }
            if (threshold_filter_enabled) {
                set_filter_option(threshold_filter, RS2_OPTION_MIN_DISTANCE, filter_min_depth);
                set_filter_option(threshold_filter, RS2_OPTION_MAX_DISTANCE, filter_max_depth);
                process_filter(threshold_filter, "threshold", filtered_depth, next_filter_status);
            }
            const bool entered_disparity_domain = depth_to_disparity_filter_enabled;
            if (entered_disparity_domain) {
                process_filter(depth_to_disparity_filter, "depth2disp", filtered_depth, next_filter_status);
            }
            if (spatial_filter_enabled) {
                set_filter_option(spatial_filter, RS2_OPTION_FILTER_SMOOTH_ALPHA, 0.50f);
                set_filter_option(spatial_filter, RS2_OPTION_FILTER_SMOOTH_DELTA, 20.0f);
                set_filter_option(spatial_filter, RS2_OPTION_FILTER_MAGNITUDE, 2.0f);
                set_filter_option(spatial_filter, RS2_OPTION_HOLES_FILL, 0.0f);
                process_filter(spatial_filter, "spatial", filtered_depth, next_filter_status);
            }
            if (temporal_filter_enabled) {
                set_filter_option(temporal_filter, RS2_OPTION_FILTER_SMOOTH_ALPHA, 0.40f);
                set_filter_option(temporal_filter, RS2_OPTION_FILTER_SMOOTH_DELTA, 20.0f);
                set_filter_option(temporal_filter, RS2_OPTION_HOLES_FILL, 3.0f);
                process_filter(temporal_filter, "temporal", filtered_depth, next_filter_status);
            }
            if (entered_disparity_domain) {
                process_filter(disparity_to_depth_filter, "disp2depth", filtered_depth, next_filter_status);
            } else if (disparity_to_depth_filter_enabled) {
                append_skip_status(next_filter_status, "disp2depth");
            }
            if (hole_filling_filter_enabled) {
                set_filter_option(hole_filling_filter, RS2_OPTION_HOLES_FILL, float(hole_filling_mode));
                process_filter(hole_filling_filter, "hole", filtered_depth, next_filter_status);
            }
            rs2::depth_frame maybe_depth = filtered_depth.as<rs2::depth_frame>();
            if (maybe_depth) {
                depth_frame = maybe_depth;
                filter_status = next_filter_status;
            } else {
                filter_status = next_filter_status + " skipped_result_not_depth";
            }
        } else {
            filter_status = "filters=off";
        }

        const int src_w = depth_frame.get_width();
        const int src_h = depth_frame.get_height();
        const int color_w = color_frame.get_width();
        const int color_h = color_frame.get_height();
        const int grid_stride = std::max(1, stride);
        const int grid_w = (src_w + grid_stride - 1) / grid_stride;
        const int grid_h = (src_h + grid_stride - 1) / grid_stride;
        if (grid_w <= 0 || grid_h <= 0) {
            return false;
        }

        PackedByteArray next_depth;
        next_depth.resize(grid_w * grid_h * 4);
        PackedByteArray next_color;
        if (color_output_enabled) {
            next_color.resize(grid_w * grid_h * 4);
        }

        const uint16_t *depth_data = static_cast<const uint16_t *>(depth_frame.get_data());
        float *depth_out = reinterpret_cast<float *>(next_depth.ptrw());
        const uint8_t *color_data = color_output_enabled ? static_cast<const uint8_t *>(color_frame.get_data()) : nullptr;
        uint8_t *color_out = color_output_enabled ? next_color.ptrw() : nullptr;
        const int color_bpp = color_frame.get_bytes_per_pixel();
        const int color_stride = color_frame.get_stride_in_bytes();
        const float active_depth_units = depth_frame.get_units();
        int next_valid_depth_pixels = 0;

        for (int y = 0; y < grid_h; ++y) {
            const int sy = std::min(y * grid_stride, src_h - 1);
            for (int x = 0; x < grid_w; ++x) {
                const int sx = std::min(x * grid_stride, src_w - 1);
                const int dst_index = y * grid_w + x;
                const int src_index = sy * src_w + sx;
                const float depth_m = float(depth_data[src_index]) * active_depth_units;
                depth_out[dst_index] = depth_m;
                if (depth_m >= filter_min_depth && depth_m <= filter_max_depth) {
                    next_valid_depth_pixels++;
                }

                if (color_output_enabled) {
                    const int cx = std::min(std::max(0, int((float(sx) + 0.5f) * float(color_w) / float(std::max(1, src_w)))), std::max(0, color_w - 1));
                    const int cy = std::min(std::max(0, int((float(sy) + 0.5f) * float(color_h) / float(std::max(1, src_h)))), std::max(0, color_h - 1));
                    const uint8_t *bgr = color_data + cy * color_stride + cx * color_bpp;
                    color_out[dst_index * 4 + 0] = color_bpp >= 3 ? bgr[2] : bgr[0];
                    color_out[dst_index * 4 + 1] = color_bpp >= 2 ? bgr[1] : bgr[0];
                    color_out[dst_index * 4 + 2] = bgr[0];
                    color_out[dst_index * 4 + 3] = 255;
                }
            }
        }

        rs2::video_stream_profile depth_profile = depth_frame.get_profile().as<rs2::video_stream_profile>();
        const rs2_intrinsics rs_intrinsics = depth_profile.get_intrinsics();
        intrinsics = Vector4(rs_intrinsics.fx, rs_intrinsics.fy, rs_intrinsics.ppx, rs_intrinsics.ppy);
        source_width = src_w;
        source_height = src_h;
        width = grid_w;
        height = grid_h;
        valid_depth_pixels = next_valid_depth_pixels;
        frame_id++;
        sequence += 2;
        const double now_sec = std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
        if (capture_fps_window_start <= 0.0) {
            capture_fps_window_start = now_sec;
            capture_fps_frames = 0;
        }
        capture_fps_frames++;
        const double fps_elapsed = now_sec - capture_fps_window_start;
        if (fps_elapsed >= 1.0) {
            capture_fps = double(capture_fps_frames) / fps_elapsed;
            capture_fps_frames = 0;
            capture_fps_window_start = now_sec;
        }
        depth_image = Image::create_from_data(width, height, false, Image::FORMAT_RF, next_depth);
        if (color_output_enabled) {
            color_image = Image::create_from_data(width, height, false, Image::FORMAT_RGBA8, next_color);
        } else {
            color_image.unref();
        }
        status = String("RealSense direct capture active: ") + stream_profile;
        const double valid_percent = width > 0 && height > 0 ? (100.0 * double(valid_depth_pixels) / double(width * height)) : 0.0;
        filter_status += String(" src=") + String::num_int64(src_w) + "x" + String::num_int64(src_h)
            + " out=" + String::num_int64(width) + "x" + String::num_int64(height)
            + " valid=" + String::num_int64(valid_depth_pixels) + "/" + String::num_int64(width * height)
            + " (" + String::num(valid_percent, 1) + "%)";
        return true;
    } catch (const rs2::error &e) {
        status = String("RealSense direct poll failed: ") + e.what();
        UtilityFunctions::push_warning(status);
        close();
        return false;
    } catch (const std::exception &e) {
        status = String("RealSense direct poll failed: ") + e.what();
        UtilityFunctions::push_warning(status);
        close();
        return false;
    }
}
#else
bool RealSenseDirectFrameSource::open() {
    opened = false;
    clear_frame();
    status = "RealSense direct capture unavailable: GDExtension was built without librealsense2 SDK headers/libs.";
    UtilityFunctions::push_warning(status);
    return false;
}

void RealSenseDirectFrameSource::close() {
    opened = false;
    clear_frame();
    status = "RealSense direct capture is closed";
}

bool RealSenseDirectFrameSource::poll() {
    return false;
}
#endif

bool RealSenseDirectFrameSource::is_open() const { return opened; }
uint64_t RealSenseDirectFrameSource::get_sequence() const { return sequence; }
uint64_t RealSenseDirectFrameSource::get_frame_id() const { return frame_id; }
double RealSenseDirectFrameSource::get_capture_fps() const { return capture_fps; }
int RealSenseDirectFrameSource::get_width() const { return width; }
int RealSenseDirectFrameSource::get_height() const { return height; }
int RealSenseDirectFrameSource::get_source_width() const { return source_width; }
int RealSenseDirectFrameSource::get_source_height() const { return source_height; }
Vector4 RealSenseDirectFrameSource::get_intrinsics() const { return intrinsics; }
Ref<Image> RealSenseDirectFrameSource::get_depth_image() const { return depth_image; }
Ref<Image> RealSenseDirectFrameSource::get_color_image() const { return color_image; }
String RealSenseDirectFrameSource::get_status() const { return status; }
String RealSenseDirectFrameSource::get_filter_status() const { return filter_status; }
