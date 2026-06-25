#pragma once

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include <vector>

#ifdef REALSENSE_DIRECT_ENABLED
#include <librealsense2/rs.hpp>
#endif

class RealSenseDirectFrameSource : public godot::RefCounted {
    GDCLASS(RealSenseDirectFrameSource, godot::RefCounted)

public:
    RealSenseDirectFrameSource();
    ~RealSenseDirectFrameSource();

    void set_stream_profile(const godot::String &p_profile);
    godot::String get_stream_profile() const;
    void set_stride(int p_stride);
    int get_stride() const;
    void set_color_output_enabled(bool p_enabled);
    bool get_color_output_enabled() const;
    void set_depth_source(const godot::String &p_source);
    godot::String get_depth_source() const;
    void set_fast_foundation_backend(const godot::String &p_backend);
    godot::String get_fast_foundation_backend() const;
    void set_fast_foundation_profile(const godot::String &p_profile);
    godot::String get_fast_foundation_profile() const;
    void set_fast_foundation_model_path(const godot::String &p_path);
    godot::String get_fast_foundation_model_path() const;
    void set_post_processing_enabled(bool p_enabled);
    void set_decimation_filter_enabled(bool p_enabled);
    void set_decimation_magnitude(int p_magnitude);
    void set_rotation_filter_enabled(bool p_enabled);
    void set_hdr_merge_filter_enabled(bool p_enabled);
    void set_sequence_id_filter_enabled(bool p_enabled);
    void set_threshold_filter_enabled(bool p_enabled);
    void set_depth_to_disparity_filter_enabled(bool p_enabled);
    void set_spatial_filter_enabled(bool p_enabled);
    void set_temporal_filter_enabled(bool p_enabled);
    void set_hole_filling_filter_enabled(bool p_enabled);
    void set_disparity_to_depth_filter_enabled(bool p_enabled);
    void set_filter_depth_range(float p_min_depth, float p_max_depth);
    void set_hole_filling_mode(int p_mode);
    void reset_post_processing_filters();
    bool open();
    void close();
    bool is_open() const;
    bool poll();

    uint64_t get_sequence() const;
    uint64_t get_frame_id() const;
    double get_capture_fps() const;
    int get_width() const;
    int get_height() const;
    int get_source_width() const;
    int get_source_height() const;
    godot::Vector4 get_intrinsics() const;
    godot::Ref<godot::Image> get_depth_image() const;
    godot::Ref<godot::Image> get_color_image() const;
    godot::String get_status() const;
    godot::String get_filter_status() const;

protected:
    static void _bind_methods();

private:
    struct StreamSettings {
        int depth_width = 848;
        int depth_height = 480;
        int depth_fps = 30;
        int color_width = 1280;
        int color_height = 720;
        int color_fps = 30;
    };

    godot::String stream_profile = "viewer30";
    int stride = 1;
    bool color_output_enabled = true;
    bool post_processing_enabled = false;
    bool decimation_filter_enabled = true;
    int decimation_magnitude = 2;
    bool rotation_filter_enabled = false;
    bool hdr_merge_filter_enabled = true;
    bool sequence_id_filter_enabled = false;
    bool threshold_filter_enabled = false;
    bool depth_to_disparity_filter_enabled = true;
    bool spatial_filter_enabled = true;
    bool temporal_filter_enabled = true;
    bool hole_filling_filter_enabled = false;
    bool disparity_to_depth_filter_enabled = true;
    float filter_min_depth = 0.2f;
    float filter_max_depth = 4.5f;
    int hole_filling_mode = 1;
    uint64_t sequence = 0;
    uint64_t frame_id = 0;
    double capture_fps = 0.0;
    int capture_fps_frames = 0;
    double capture_fps_window_start = 0.0;
    int width = 0;
    int height = 0;
    int source_width = 0;
    int source_height = 0;
    godot::Vector4 intrinsics;
    godot::Ref<godot::Image> depth_image;
    godot::Ref<godot::Image> color_image;
    godot::String status = "RealSense direct capture is closed";
    godot::String filter_status = "filters=off";
    int valid_depth_pixels = 0;
    godot::String depth_source = "sdk_depth";
    godot::String fast_foundation_backend = "onnx_cuda";
    godot::String fast_foundation_profile = "fast_192x384_i2";
    godot::String fast_foundation_model_path;
    double fast_foundation_model_ms = 0.0;
    double fast_foundation_pre_ms = 0.0;
    double fast_foundation_depth_ms = 0.0;

    StreamSettings resolve_stream_settings() const;
    void clear_frame();
    godot::String resolve_fast_foundation_model_path() const;

#ifdef REALSENSE_DIRECT_ENABLED
    bool opened = false;
    float depth_scale = 0.001f;
    bool fast_foundation_loaded = false;
    int fast_foundation_input_width = 0;
    int fast_foundation_input_height = 0;
    float fast_foundation_baseline_m = 0.0f;
    void *fast_foundation_session = nullptr;
    void *fast_foundation_memory_info = nullptr;
    std::vector<float> fast_foundation_left_input;
    std::vector<float> fast_foundation_right_input;
    std::vector<float> fast_foundation_disparity;
    std::vector<uint8_t> fast_foundation_left_resized;
    std::vector<uint8_t> fast_foundation_right_resized;
    rs2::pipeline pipeline;
    rs2::pipeline_profile pipeline_profile;
    rs2::align align_to_depth;
    rs2::decimation_filter decimation_filter;
    rs2::rotation_filter rotation_filter;
    rs2::hdr_merge hdr_merge_filter;
    rs2::sequence_id_filter sequence_id_filter;
    rs2::threshold_filter threshold_filter;
    rs2::disparity_transform depth_to_disparity_filter;
    rs2::spatial_filter spatial_filter;
    rs2::temporal_filter temporal_filter;
    rs2::hole_filling_filter hole_filling_filter;
    rs2::disparity_transform disparity_to_depth_filter;
    bool is_fast_foundation_source() const;
    void reset_fast_foundation_runtime();
    bool initialize_fast_foundation_runtime();
    bool poll_sdk_depth();
    bool poll_fast_foundation();
#else
    bool opened = false;
#endif
};
