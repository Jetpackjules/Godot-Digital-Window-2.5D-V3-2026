#pragma once

#include "realsense_shared_memory_reader.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
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
    void set_min_depth(double p_depth);
    double get_min_depth() const;
    void set_max_depth(double p_depth);
    double get_max_depth() const;
    void set_render_connected_mesh(bool p_enabled);
    bool get_render_connected_mesh() const;
    void set_mesh_max_edge(double p_edge);
    double get_mesh_max_edge() const;
    void set_mesh_max_depth_delta(double p_delta);
    double get_mesh_max_depth_delta() const;
    void set_texture_map_mesh(bool p_enabled);
    bool get_texture_map_mesh() const;
    void set_mesh_min_triangle_area(double p_area);
    double get_mesh_min_triangle_area() const;
    void set_mesh_max_color_delta(double p_delta);
    double get_mesh_max_color_delta() const;
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
    bool is_connected() const;
    double get_render_fps() const;
    int get_last_triangle_count() const;
    int get_last_point_count() const;

protected:
    static void _bind_methods();

private:
    godot::String shared_memory_name = "realsense_point_cloud_grid";
    double point_pixel_size = 2.0;
    double min_depth = 0.2;
    double max_depth = 4.5;
    bool render_connected_mesh = false;
    bool texture_map_mesh = false;
    double mesh_max_edge = 0.08;
    double mesh_max_depth_delta = 0.08;
    double mesh_min_triangle_area = 0.000025;
    double mesh_max_color_delta = 2.0;
    bool delay_enabled = false;
    double primary_delay_ms = 0.0;
    double secondary_delay_ms = 0.0;
    godot::String secondary_shared_memory_name = "oakd_point_cloud_grid";
    bool secondary_enabled = false;
    godot::Transform3D secondary_transform;
    godot::Ref<RealSenseSharedMemoryReader> reader;
    godot::Ref<RealSenseSharedMemoryReader> secondary_reader;
    godot::Ref<godot::ImageTexture> depth_texture;
    godot::Ref<godot::ImageTexture> color_texture;
    godot::Ref<godot::ShaderMaterial> material;
    godot::Ref<godot::StandardMaterial3D> texture_material;
    godot::Ref<godot::StandardMaterial3D> vertex_color_material;
    int grid_width = 0;
    int grid_height = 0;
    int grid_stride = 0;
    int frames = 0;
    double fps_accum = 0.0;
    double render_fps = 0.0;
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
    void ensure_texture_material();
    void ensure_vertex_color_material();
    void rebuild_mesh(int p_width, int p_height, int p_stride);
    void push_frame_history(std::deque<FrameSnapshot> &p_history, const godot::Ref<RealSenseSharedMemoryReader> &p_reader, const godot::Ref<godot::Image> &p_depth_image, const godot::Ref<godot::Image> &p_color_image);
    FrameSnapshot select_frame_for_delay(const std::deque<FrameSnapshot> &p_history, double p_delay_ms, const godot::Ref<RealSenseSharedMemoryReader> &p_reader, const godot::Ref<godot::Image> &p_depth_image, const godot::Ref<godot::Image> &p_color_image) const;
    double now_seconds() const;
    int rebuild_cpu_connected_mesh(const godot::Ref<godot::Image> &p_depth_image, const godot::Ref<godot::Image> &p_color_image);
    int rebuild_cpu_combined_mesh(const godot::Ref<godot::Image> &p_depth_image, const godot::Ref<godot::Image> &p_color_image);
    int append_cpu_grid_surface(
        godot::Ref<godot::ArrayMesh> &p_mesh,
        const godot::Ref<RealSenseSharedMemoryReader> &p_reader,
        const godot::Ref<godot::Image> &p_depth_image,
        const godot::Ref<godot::Image> &p_color_image,
        const godot::Transform3D &p_transform,
        int &r_point_count
    );
    bool triangle_valid(const godot::PackedVector3Array &p_vertices, int p_a, int p_b, int p_c, double p_max_edge_sq) const;
    bool triangle_color_valid(const godot::PackedColorArray &p_colors, int p_a, int p_b, int p_c) const;
    void update_material_params();
};
