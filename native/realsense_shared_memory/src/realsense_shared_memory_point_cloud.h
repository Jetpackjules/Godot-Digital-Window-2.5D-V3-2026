#pragma once

#include "realsense_shared_memory_reader.h"
#include "realsense_direct_frame_source.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include <deque>

class RealSenseSharedMemoryPointCloud : public godot::MeshInstance3D {
    GDCLASS(RealSenseSharedMemoryPointCloud, godot::MeshInstance3D)

public:
    RealSenseSharedMemoryPointCloud();
    ~RealSenseSharedMemoryPointCloud();

    void _ready() override;
    void _process(double p_delta) override;

    void set_shared_memory_name(const godot::String &p_name);
    godot::String get_shared_memory_name() const;
    void set_point_pixel_size(double p_size);
    double get_point_pixel_size() const;
    void set_circular_point_splats(bool p_enabled);
    bool get_circular_point_splats() const;
    void set_point_cleanup_enabled(bool p_enabled);
    bool get_point_cleanup_enabled() const;
    void set_point_cleanup_depth_delta(double p_delta);
    double get_point_cleanup_depth_delta() const;
    void set_point_cleanup_min_neighbors(double p_count);
    double get_point_cleanup_min_neighbors() const;
    void set_min_depth(double p_depth);
    double get_min_depth() const;
    void set_max_depth(double p_depth);
    double get_max_depth() const;
    void set_render_connected_mesh(bool p_enabled);
    bool get_render_connected_mesh() const;
    void set_gpu_connected_mesh(bool p_enabled);
    bool get_gpu_connected_mesh() const;
    void set_cpu_project_points(bool p_enabled);
    bool get_cpu_project_points() const;
    void set_color_enabled(bool p_enabled);
    bool get_color_enabled() const;
    void set_mesh_max_edge(double p_edge);
    double get_mesh_max_edge() const;
    void set_mesh_max_depth_delta(double p_delta);
    double get_mesh_max_depth_delta() const;
    void set_texture_map_mesh(bool p_enabled);
    bool get_texture_map_mesh() const;
    void set_gpu_mesh_compute_indices(bool p_enabled);
    bool get_gpu_mesh_compute_indices() const;
    void set_gpu_mesh_static_shader(bool p_enabled);
    bool get_gpu_mesh_static_shader() const;
    void set_mesh_min_triangle_area(double p_area);
    double get_mesh_min_triangle_area() const;
    void set_mesh_max_color_delta(double p_delta);
    double get_mesh_max_color_delta() const;
    void set_edge_feather_enabled(bool p_enabled);
    bool get_edge_feather_enabled() const;
    void set_edge_feather_width(double p_width);
    double get_edge_feather_width() const;
    void set_edge_feather_min_alpha(double p_alpha);
    double get_edge_feather_min_alpha() const;
    void set_delay_enabled(bool p_enabled);
    bool get_delay_enabled() const;
    void set_primary_delay_ms(double p_delay_ms);
    double get_primary_delay_ms() const;
    void set_secondary_delay_ms(double p_delay_ms);
    double get_secondary_delay_ms() const;
    void set_secondary_shared_memory_name(const godot::String &p_name);
    godot::String get_secondary_shared_memory_name() const;
    void set_secondary_enabled(bool p_enabled);
    bool get_secondary_enabled() const;
    void set_secondary_transform(const godot::Transform3D &p_transform);
    godot::Transform3D get_secondary_transform() const;
    void set_direct_realsense_enabled(bool p_enabled);
    bool get_direct_realsense_enabled() const;
    void set_direct_realsense_stream_profile(const godot::String &p_profile);
    godot::String get_direct_realsense_stream_profile() const;
    void set_direct_realsense_depth_source(const godot::String &p_source);
    godot::String get_direct_realsense_depth_source() const;
    void set_direct_realsense_fast_foundation_backend(const godot::String &p_backend);
    godot::String get_direct_realsense_fast_foundation_backend() const;
    void set_direct_realsense_fast_foundation_profile(const godot::String &p_profile);
    godot::String get_direct_realsense_fast_foundation_profile() const;
    void set_direct_realsense_fast_foundation_model_path(const godot::String &p_path);
    godot::String get_direct_realsense_fast_foundation_model_path() const;
    void set_direct_realsense_stride(int p_stride);
    int get_direct_realsense_stride() const;
    void set_direct_realsense_filter_config(const godot::Dictionary &p_config);
    godot::String get_direct_realsense_status() const;
    double get_direct_realsense_capture_fps() const;
    bool is_connected() const;
    double get_render_fps() const;
    double get_display_frame_age_ms() const;
    int get_last_triangle_count() const;
    int get_last_point_count() const;

protected:
    static void _bind_methods();

private:
    godot::String shared_memory_name = "realsense_point_cloud_grid";
    double point_pixel_size = 2.0;
    bool circular_point_splats = false;
    bool point_cleanup_enabled = false;
    double point_cleanup_depth_delta = 0.06;
    double point_cleanup_min_neighbors = 2.0;
    double min_depth = 0.2;
    double max_depth = 4.5;
    bool render_connected_mesh = false;
    bool gpu_connected_mesh = false;
    bool cpu_project_points = false;
    bool color_enabled = true;
    bool texture_map_mesh = false;
    bool gpu_mesh_compute_indices = false;
    bool gpu_mesh_static_shader = false;
    double mesh_max_edge = 0.08;
    double mesh_max_depth_delta = 0.05;
    double mesh_min_triangle_area = 0.0;
    double mesh_max_color_delta = 2.0;
    bool edge_feather_enabled = false;
    double edge_feather_width = 0.035;
    double edge_feather_min_alpha = 0.20;
    bool delay_enabled = false;
    double primary_delay_ms = 0.0;
    double secondary_delay_ms = 0.0;
    godot::String secondary_shared_memory_name = "oakd_point_cloud_grid";
    bool secondary_enabled = false;
    godot::Transform3D secondary_transform;
    godot::Ref<RealSenseSharedMemoryReader> reader;
    godot::Ref<RealSenseSharedMemoryReader> secondary_reader;
    godot::Ref<RealSenseDirectFrameSource> direct_realsense;
    godot::Ref<godot::ImageTexture> depth_texture;
    godot::Ref<godot::ImageTexture> color_texture;
    int depth_texture_width = 0;
    int depth_texture_height = 0;
    int color_texture_width = 0;
    int color_texture_height = 0;
    godot::Ref<godot::ShaderMaterial> material;
    bool material_gpu_mesh_mode = false;
    bool material_texture_map_mode = false;
    bool material_static_shader_mesh_mode = false;
    godot::Ref<godot::ShaderMaterial> cpu_point_material;
    godot::Ref<godot::StandardMaterial3D> texture_material;
    godot::Ref<godot::StandardMaterial3D> vertex_color_material;
    int grid_width = 0;
    int grid_height = 0;
    int grid_stride = 0;
    int gpu_mesh_cache_width = 0;
    int gpu_mesh_cache_height = 0;
    int gpu_mesh_cache_stride = 0;
    int current_width = 0;
    int current_height = 0;
    int current_stride = 1;
    godot::Vector4 current_intrinsics;
    bool direct_realsense_enabled = false;
    godot::String direct_realsense_stream_profile = "viewer30";
    godot::String direct_realsense_depth_source = "sdk_depth";
    godot::String direct_realsense_fast_foundation_backend = "onnx_cuda";
    godot::String direct_realsense_fast_foundation_profile = "fast_192x384_i2";
    godot::String direct_realsense_fast_foundation_model_path;
    int direct_realsense_stride = 1;
    godot::String direct_realsense_status = "RealSense direct capture is disabled";
    bool direct_realsense_post_processing_enabled = false;
    bool direct_realsense_decimation_filter_enabled = true;
    int direct_realsense_decimation_magnitude = 2;
    bool direct_realsense_rotation_filter_enabled = false;
    bool direct_realsense_hdr_merge_filter_enabled = true;
    bool direct_realsense_sequence_id_filter_enabled = false;
    bool direct_realsense_threshold_filter_enabled = false;
    bool direct_realsense_depth_to_disparity_filter_enabled = true;
    bool direct_realsense_spatial_filter_enabled = true;
    bool direct_realsense_temporal_filter_enabled = true;
    bool direct_realsense_hole_filling_filter_enabled = false;
    bool direct_realsense_disparity_to_depth_filter_enabled = true;
    int direct_realsense_hole_filling_mode = 1;
    godot::PackedVector3Array gpu_mesh_vertices;
    godot::PackedVector2Array gpu_mesh_uvs;
    godot::RenderingDevice *mesh_compute_rd = nullptr;
    godot::RID mesh_compute_shader;
    godot::RID mesh_compute_pipeline;
    godot::RID mesh_compute_depth_buffer;
    godot::RID mesh_compute_index_buffer;
    godot::RID mesh_compute_counter_buffer;
    godot::RID mesh_compute_uniform_set;
    int mesh_compute_width = 0;
    int mesh_compute_height = 0;
    bool mesh_compute_failed = false;
    int frames = 0;
    double fps_accum = 0.0;
    double render_fps = 0.0;
    double last_display_frame_seconds = 0.0;
    int last_triangle_count = 0;
    int last_point_count = 0;

    struct FrameSnapshot {
        uint64_t sequence = 0;
        int width = 0;
        int height = 0;
        int stride = 1;
        godot::Vector4 intrinsics;
        godot::Ref<godot::Image> depth_image;
        godot::Ref<godot::Image> color_image;
        double timestamp_sec = 0.0;
    };

    std::deque<FrameSnapshot> primary_history;
    std::deque<FrameSnapshot> secondary_history;

    void ensure_material();
    void ensure_cpu_point_material();
    void ensure_texture_material();
    void ensure_vertex_color_material();
    void rebuild_mesh(int p_width, int p_height, int p_stride);
    void push_frame_history(std::deque<FrameSnapshot> &p_history, const FrameSnapshot &p_frame);
    void push_reader_frame_history(std::deque<FrameSnapshot> &p_history, const godot::Ref<RealSenseSharedMemoryReader> &p_reader, const godot::Ref<godot::Image> &p_depth_image, const godot::Ref<godot::Image> &p_color_image);
    FrameSnapshot select_frame_for_delay(const std::deque<FrameSnapshot> &p_history, double p_delay_ms, const FrameSnapshot &p_latest) const;
    FrameSnapshot make_reader_snapshot(const godot::Ref<RealSenseSharedMemoryReader> &p_reader, const godot::Ref<godot::Image> &p_depth_image, const godot::Ref<godot::Image> &p_color_image) const;
    FrameSnapshot make_direct_snapshot(const godot::Ref<RealSenseDirectFrameSource> &p_source, const godot::Ref<godot::Image> &p_depth_image, const godot::Ref<godot::Image> &p_color_image) const;
    double now_seconds() const;
    int rebuild_cpu_connected_mesh(const godot::Ref<godot::Image> &p_depth_image, const godot::Ref<godot::Image> &p_color_image);
    int rebuild_gpu_connected_mesh(const godot::Ref<godot::Image> &p_depth_image);
    void release_gpu_mesh_compute_resources();
    bool ensure_gpu_mesh_compute_resources(int p_width, int p_height);
    bool rebuild_gpu_mesh_indices_compute(
        const godot::PackedByteArray &p_depth_data,
        int p_width,
        int p_height,
        int p_stride,
        const godot::Vector4 &p_intrinsics,
        godot::PackedInt32Array &r_indices
    );
    int rebuild_cpu_point_cloud(const godot::Ref<godot::Image> &p_depth_image, const godot::Ref<godot::Image> &p_color_image);
    int rebuild_cpu_combined_mesh(const godot::Ref<godot::Image> &p_depth_image, const godot::Ref<godot::Image> &p_color_image);
    int append_cpu_grid_surface(
        godot::Ref<godot::ArrayMesh> &p_mesh,
        const godot::Ref<RealSenseSharedMemoryReader> &p_reader,
        const godot::Ref<godot::Image> &p_depth_image,
        const godot::Ref<godot::Image> &p_color_image,
        const godot::Transform3D &p_transform,
        int &r_point_count
    );
    godot::Color decode_point_color(const godot::PackedByteArray &p_color_data, int p_color_offset) const;
    bool triangle_valid(const godot::PackedVector3Array &p_vertices, int p_a, int p_b, int p_c, double p_max_edge_sq) const;
    bool triangle_color_valid(const godot::PackedColorArray &p_colors, int p_a, int p_b, int p_c) const;
    void update_material_params();
    void apply_direct_realsense_filter_settings();
};
