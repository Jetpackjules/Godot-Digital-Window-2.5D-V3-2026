#include "realsense_shared_memory_point_cloud.h"

#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>

using namespace godot;

RealSenseSharedMemoryPointCloud::RealSenseSharedMemoryPointCloud() {
    reader.instantiate();
    secondary_reader.instantiate();
    secondary_transform = Transform3D();
}

RealSenseSharedMemoryPointCloud::~RealSenseSharedMemoryPointCloud() {
    if (reader.is_valid()) {
        reader->close();
    }
    if (secondary_reader.is_valid()) {
        secondary_reader->close();
    }
}

void RealSenseSharedMemoryPointCloud::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_shared_memory_name", "name"), &RealSenseSharedMemoryPointCloud::set_shared_memory_name);
    ClassDB::bind_method(D_METHOD("get_shared_memory_name"), &RealSenseSharedMemoryPointCloud::get_shared_memory_name);
    ClassDB::bind_method(D_METHOD("set_point_pixel_size", "size"), &RealSenseSharedMemoryPointCloud::set_point_pixel_size);
    ClassDB::bind_method(D_METHOD("get_point_pixel_size"), &RealSenseSharedMemoryPointCloud::get_point_pixel_size);
    ClassDB::bind_method(D_METHOD("set_circular_point_splats", "enabled"), &RealSenseSharedMemoryPointCloud::set_circular_point_splats);
    ClassDB::bind_method(D_METHOD("get_circular_point_splats"), &RealSenseSharedMemoryPointCloud::get_circular_point_splats);
    ClassDB::bind_method(D_METHOD("set_point_cleanup_enabled", "enabled"), &RealSenseSharedMemoryPointCloud::set_point_cleanup_enabled);
    ClassDB::bind_method(D_METHOD("get_point_cleanup_enabled"), &RealSenseSharedMemoryPointCloud::get_point_cleanup_enabled);
    ClassDB::bind_method(D_METHOD("set_point_cleanup_depth_delta", "delta"), &RealSenseSharedMemoryPointCloud::set_point_cleanup_depth_delta);
    ClassDB::bind_method(D_METHOD("get_point_cleanup_depth_delta"), &RealSenseSharedMemoryPointCloud::get_point_cleanup_depth_delta);
    ClassDB::bind_method(D_METHOD("set_point_cleanup_min_neighbors", "count"), &RealSenseSharedMemoryPointCloud::set_point_cleanup_min_neighbors);
    ClassDB::bind_method(D_METHOD("get_point_cleanup_min_neighbors"), &RealSenseSharedMemoryPointCloud::get_point_cleanup_min_neighbors);
    ClassDB::bind_method(D_METHOD("set_min_depth", "depth"), &RealSenseSharedMemoryPointCloud::set_min_depth);
    ClassDB::bind_method(D_METHOD("get_min_depth"), &RealSenseSharedMemoryPointCloud::get_min_depth);
    ClassDB::bind_method(D_METHOD("set_max_depth", "depth"), &RealSenseSharedMemoryPointCloud::set_max_depth);
    ClassDB::bind_method(D_METHOD("get_max_depth"), &RealSenseSharedMemoryPointCloud::get_max_depth);
    ClassDB::bind_method(D_METHOD("set_render_connected_mesh", "enabled"), &RealSenseSharedMemoryPointCloud::set_render_connected_mesh);
    ClassDB::bind_method(D_METHOD("get_render_connected_mesh"), &RealSenseSharedMemoryPointCloud::get_render_connected_mesh);
    ClassDB::bind_method(D_METHOD("set_gpu_connected_mesh", "enabled"), &RealSenseSharedMemoryPointCloud::set_gpu_connected_mesh);
    ClassDB::bind_method(D_METHOD("get_gpu_connected_mesh"), &RealSenseSharedMemoryPointCloud::get_gpu_connected_mesh);
    ClassDB::bind_method(D_METHOD("set_cpu_project_points", "enabled"), &RealSenseSharedMemoryPointCloud::set_cpu_project_points);
    ClassDB::bind_method(D_METHOD("get_cpu_project_points"), &RealSenseSharedMemoryPointCloud::get_cpu_project_points);
    ClassDB::bind_method(D_METHOD("set_color_enabled", "enabled"), &RealSenseSharedMemoryPointCloud::set_color_enabled);
    ClassDB::bind_method(D_METHOD("get_color_enabled"), &RealSenseSharedMemoryPointCloud::get_color_enabled);
    ClassDB::bind_method(D_METHOD("set_mesh_max_edge", "edge"), &RealSenseSharedMemoryPointCloud::set_mesh_max_edge);
    ClassDB::bind_method(D_METHOD("get_mesh_max_edge"), &RealSenseSharedMemoryPointCloud::get_mesh_max_edge);
    ClassDB::bind_method(D_METHOD("set_mesh_max_depth_delta", "delta"), &RealSenseSharedMemoryPointCloud::set_mesh_max_depth_delta);
    ClassDB::bind_method(D_METHOD("get_mesh_max_depth_delta"), &RealSenseSharedMemoryPointCloud::get_mesh_max_depth_delta);
    ClassDB::bind_method(D_METHOD("set_texture_map_mesh", "enabled"), &RealSenseSharedMemoryPointCloud::set_texture_map_mesh);
    ClassDB::bind_method(D_METHOD("get_texture_map_mesh"), &RealSenseSharedMemoryPointCloud::get_texture_map_mesh);
    ClassDB::bind_method(D_METHOD("set_mesh_min_triangle_area", "area"), &RealSenseSharedMemoryPointCloud::set_mesh_min_triangle_area);
    ClassDB::bind_method(D_METHOD("get_mesh_min_triangle_area"), &RealSenseSharedMemoryPointCloud::get_mesh_min_triangle_area);
    ClassDB::bind_method(D_METHOD("set_mesh_max_color_delta", "delta"), &RealSenseSharedMemoryPointCloud::set_mesh_max_color_delta);
    ClassDB::bind_method(D_METHOD("get_mesh_max_color_delta"), &RealSenseSharedMemoryPointCloud::get_mesh_max_color_delta);
    ClassDB::bind_method(D_METHOD("set_edge_feather_enabled", "enabled"), &RealSenseSharedMemoryPointCloud::set_edge_feather_enabled);
    ClassDB::bind_method(D_METHOD("get_edge_feather_enabled"), &RealSenseSharedMemoryPointCloud::get_edge_feather_enabled);
    ClassDB::bind_method(D_METHOD("set_edge_feather_width", "width"), &RealSenseSharedMemoryPointCloud::set_edge_feather_width);
    ClassDB::bind_method(D_METHOD("get_edge_feather_width"), &RealSenseSharedMemoryPointCloud::get_edge_feather_width);
    ClassDB::bind_method(D_METHOD("set_edge_feather_min_alpha", "alpha"), &RealSenseSharedMemoryPointCloud::set_edge_feather_min_alpha);
    ClassDB::bind_method(D_METHOD("get_edge_feather_min_alpha"), &RealSenseSharedMemoryPointCloud::get_edge_feather_min_alpha);
    ClassDB::bind_method(D_METHOD("set_delay_enabled", "enabled"), &RealSenseSharedMemoryPointCloud::set_delay_enabled);
    ClassDB::bind_method(D_METHOD("get_delay_enabled"), &RealSenseSharedMemoryPointCloud::get_delay_enabled);
    ClassDB::bind_method(D_METHOD("set_primary_delay_ms", "delay_ms"), &RealSenseSharedMemoryPointCloud::set_primary_delay_ms);
    ClassDB::bind_method(D_METHOD("get_primary_delay_ms"), &RealSenseSharedMemoryPointCloud::get_primary_delay_ms);
    ClassDB::bind_method(D_METHOD("set_secondary_delay_ms", "delay_ms"), &RealSenseSharedMemoryPointCloud::set_secondary_delay_ms);
    ClassDB::bind_method(D_METHOD("get_secondary_delay_ms"), &RealSenseSharedMemoryPointCloud::get_secondary_delay_ms);
    ClassDB::bind_method(D_METHOD("set_secondary_shared_memory_name", "name"), &RealSenseSharedMemoryPointCloud::set_secondary_shared_memory_name);
    ClassDB::bind_method(D_METHOD("get_secondary_shared_memory_name"), &RealSenseSharedMemoryPointCloud::get_secondary_shared_memory_name);
    ClassDB::bind_method(D_METHOD("set_secondary_enabled", "enabled"), &RealSenseSharedMemoryPointCloud::set_secondary_enabled);
    ClassDB::bind_method(D_METHOD("get_secondary_enabled"), &RealSenseSharedMemoryPointCloud::get_secondary_enabled);
    ClassDB::bind_method(D_METHOD("set_secondary_transform", "transform"), &RealSenseSharedMemoryPointCloud::set_secondary_transform);
    ClassDB::bind_method(D_METHOD("get_secondary_transform"), &RealSenseSharedMemoryPointCloud::get_secondary_transform);
    ClassDB::bind_method(D_METHOD("is_connected"), &RealSenseSharedMemoryPointCloud::is_connected);
    ClassDB::bind_method(D_METHOD("get_render_fps"), &RealSenseSharedMemoryPointCloud::get_render_fps);
    ClassDB::bind_method(D_METHOD("get_display_frame_age_ms"), &RealSenseSharedMemoryPointCloud::get_display_frame_age_ms);
    ClassDB::bind_method(D_METHOD("get_last_triangle_count"), &RealSenseSharedMemoryPointCloud::get_last_triangle_count);
    ClassDB::bind_method(D_METHOD("get_last_point_count"), &RealSenseSharedMemoryPointCloud::get_last_point_count);

    ADD_PROPERTY(PropertyInfo(Variant::STRING, "shared_memory_name"), "set_shared_memory_name", "get_shared_memory_name");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "point_pixel_size"), "set_point_pixel_size", "get_point_pixel_size");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "circular_point_splats"), "set_circular_point_splats", "get_circular_point_splats");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "point_cleanup_enabled"), "set_point_cleanup_enabled", "get_point_cleanup_enabled");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "point_cleanup_depth_delta"), "set_point_cleanup_depth_delta", "get_point_cleanup_depth_delta");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "point_cleanup_min_neighbors"), "set_point_cleanup_min_neighbors", "get_point_cleanup_min_neighbors");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_depth"), "set_min_depth", "get_min_depth");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_depth"), "set_max_depth", "get_max_depth");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "render_connected_mesh"), "set_render_connected_mesh", "get_render_connected_mesh");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "gpu_connected_mesh"), "set_gpu_connected_mesh", "get_gpu_connected_mesh");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "cpu_project_points"), "set_cpu_project_points", "get_cpu_project_points");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "color_enabled"), "set_color_enabled", "get_color_enabled");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "mesh_max_edge"), "set_mesh_max_edge", "get_mesh_max_edge");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "mesh_max_depth_delta"), "set_mesh_max_depth_delta", "get_mesh_max_depth_delta");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "texture_map_mesh"), "set_texture_map_mesh", "get_texture_map_mesh");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "mesh_min_triangle_area"), "set_mesh_min_triangle_area", "get_mesh_min_triangle_area");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "mesh_max_color_delta"), "set_mesh_max_color_delta", "get_mesh_max_color_delta");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "edge_feather_enabled"), "set_edge_feather_enabled", "get_edge_feather_enabled");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "edge_feather_width"), "set_edge_feather_width", "get_edge_feather_width");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "edge_feather_min_alpha"), "set_edge_feather_min_alpha", "get_edge_feather_min_alpha");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "delay_enabled"), "set_delay_enabled", "get_delay_enabled");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "primary_delay_ms"), "set_primary_delay_ms", "get_primary_delay_ms");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "secondary_delay_ms"), "set_secondary_delay_ms", "get_secondary_delay_ms");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "secondary_shared_memory_name"), "set_secondary_shared_memory_name", "get_secondary_shared_memory_name");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "secondary_enabled"), "set_secondary_enabled", "get_secondary_enabled");
}

void RealSenseSharedMemoryPointCloud::_ready() {
    ensure_material();
    if (reader.is_null()) {
        reader.instantiate();
    }
    if (!reader->is_open()) {
        reader->open(shared_memory_name);
    }
    set_process(true);
}

void RealSenseSharedMemoryPointCloud::_process(double p_delta) {
    if (reader.is_null()) {
        reader.instantiate();
    }
    if (!reader->is_open()) {
        reader->open(shared_memory_name);
        if (!reader->is_open()) {
            return;
        }
    }
    if (!reader->poll()) {
        return;
    }
    last_display_frame_seconds = now_seconds();

    int width = reader->get_width();
    int height = reader->get_height();
    int stride = reader->get_stride();
    if (width <= 1 || height <= 1) {
        return;
    }
    const bool cpu_built_surface = cpu_project_points || (render_connected_mesh && !gpu_connected_mesh);
    if (!cpu_built_surface && !gpu_connected_mesh && (width != grid_width || height != grid_height || stride != grid_stride || get_mesh().is_null())) {
        rebuild_mesh(width, height, stride);
    }

    Ref<Image> depth_image = reader->get_depth_image();
    Ref<Image> color_image = reader->get_color_image();
    if (depth_image.is_null() || color_image.is_null()) {
        return;
    }
    push_frame_history(primary_history, reader, depth_image, color_image);
    FrameSnapshot primary_frame = select_frame_for_delay(primary_history, primary_delay_ms, reader, depth_image, color_image);
    if (primary_frame.depth_image.is_null() || primary_frame.color_image.is_null()) {
        return;
    }
    if (render_connected_mesh && !gpu_connected_mesh) {
        if (secondary_enabled) {
            if (secondary_reader.is_null()) {
                secondary_reader.instantiate();
            }
            if (!secondary_reader->is_open()) {
                secondary_reader->open(secondary_shared_memory_name);
            }
            if (secondary_reader->is_open()) {
                if (secondary_reader->poll()) {
                    push_frame_history(secondary_history, secondary_reader, secondary_reader->get_depth_image(), secondary_reader->get_color_image());
                }
            }
            last_triangle_count = rebuild_cpu_combined_mesh(primary_frame.depth_image, primary_frame.color_image);
        } else {
            last_triangle_count = rebuild_cpu_connected_mesh(primary_frame.depth_image, primary_frame.color_image);
        }
        frames++;
        fps_accum += p_delta;
        if (fps_accum >= 1.0) {
            render_fps = double(frames) / fps_accum;
            frames = 0;
            fps_accum = 0.0;
        }
        return;
    }
    if (cpu_project_points && !render_connected_mesh) {
        last_triangle_count = 0;
        last_point_count = rebuild_cpu_point_cloud(primary_frame.depth_image, primary_frame.color_image);
        frames++;
        fps_accum += p_delta;
        if (fps_accum >= 1.0) {
            render_fps = double(frames) / fps_accum;
            frames = 0;
            fps_accum = 0.0;
        }
        return;
    }
    if (depth_texture.is_null() || color_texture.is_null()) {
        depth_texture = ImageTexture::create_from_image(primary_frame.depth_image);
        color_texture = ImageTexture::create_from_image(primary_frame.color_image);
    } else {
        depth_texture->update(primary_frame.depth_image);
        color_texture->update(primary_frame.color_image);
    }
    ensure_material();
    set_material_override(Ref<Material>());
    update_material_params();
    if (render_connected_mesh && gpu_connected_mesh) {
        last_triangle_count = rebuild_gpu_connected_mesh(primary_frame.depth_image);
        last_point_count = width * height;
    } else {
        last_point_count = width * height;
        last_triangle_count = 0;
    }

    frames++;
    fps_accum += p_delta;
    if (fps_accum >= 1.0) {
        render_fps = double(frames) / fps_accum;
        frames = 0;
        fps_accum = 0.0;
    }
}

void RealSenseSharedMemoryPointCloud::set_shared_memory_name(const String &p_name) {
    if (shared_memory_name == p_name) {
        return;
    }
    shared_memory_name = p_name;
    if (reader.is_null()) {
        reader.instantiate();
    }
    if (reader->is_open()) {
        reader->close();
        reader->open(shared_memory_name);
    }
}

String RealSenseSharedMemoryPointCloud::get_shared_memory_name() const { return shared_memory_name; }

void RealSenseSharedMemoryPointCloud::set_point_pixel_size(double p_size) {
    if (Math::is_equal_approx(point_pixel_size, p_size)) {
        return;
    }
    point_pixel_size = p_size;
    update_material_params();
    if (cpu_project_points) {
        set_mesh(Ref<Mesh>());
    }
}

double RealSenseSharedMemoryPointCloud::get_point_pixel_size() const { return point_pixel_size; }

void RealSenseSharedMemoryPointCloud::set_circular_point_splats(bool p_enabled) {
    if (circular_point_splats == p_enabled) {
        return;
    }
    circular_point_splats = p_enabled;
    update_material_params();
    if (cpu_point_material.is_valid()) {
        cpu_point_material->set_shader_parameter("circular_point_splats", circular_point_splats);
    }
}

bool RealSenseSharedMemoryPointCloud::get_circular_point_splats() const { return circular_point_splats; }

void RealSenseSharedMemoryPointCloud::set_point_cleanup_enabled(bool p_enabled) {
    if (point_cleanup_enabled == p_enabled) {
        return;
    }
    point_cleanup_enabled = p_enabled;
    update_material_params();
    if (cpu_project_points) {
        set_mesh(Ref<Mesh>());
    }
}

bool RealSenseSharedMemoryPointCloud::get_point_cleanup_enabled() const { return point_cleanup_enabled; }

void RealSenseSharedMemoryPointCloud::set_point_cleanup_depth_delta(double p_delta) {
    if (Math::is_equal_approx(point_cleanup_depth_delta, p_delta)) {
        return;
    }
    point_cleanup_depth_delta = MAX(0.001, p_delta);
    update_material_params();
    if (cpu_project_points && point_cleanup_enabled) {
        set_mesh(Ref<Mesh>());
    }
}

double RealSenseSharedMemoryPointCloud::get_point_cleanup_depth_delta() const { return point_cleanup_depth_delta; }

void RealSenseSharedMemoryPointCloud::set_point_cleanup_min_neighbors(double p_count) {
    const double clamped = CLAMP(p_count, 0.0, 4.0);
    if (Math::is_equal_approx(point_cleanup_min_neighbors, clamped)) {
        return;
    }
    point_cleanup_min_neighbors = clamped;
    update_material_params();
    if (cpu_project_points && point_cleanup_enabled) {
        set_mesh(Ref<Mesh>());
    }
}

double RealSenseSharedMemoryPointCloud::get_point_cleanup_min_neighbors() const { return point_cleanup_min_neighbors; }

void RealSenseSharedMemoryPointCloud::set_min_depth(double p_depth) {
    if (Math::is_equal_approx(min_depth, p_depth)) {
        return;
    }
    min_depth = p_depth;
    update_material_params();
}

double RealSenseSharedMemoryPointCloud::get_min_depth() const { return min_depth; }

void RealSenseSharedMemoryPointCloud::set_max_depth(double p_depth) {
    if (Math::is_equal_approx(max_depth, p_depth)) {
        return;
    }
    max_depth = p_depth;
    update_material_params();
}

double RealSenseSharedMemoryPointCloud::get_max_depth() const { return max_depth; }

void RealSenseSharedMemoryPointCloud::set_render_connected_mesh(bool p_enabled) {
    if (render_connected_mesh == p_enabled) {
        return;
    }
    render_connected_mesh = p_enabled;
    set_mesh(Ref<Mesh>());
    grid_width = 0;
    grid_height = 0;
    grid_stride = 0;
}

bool RealSenseSharedMemoryPointCloud::get_render_connected_mesh() const { return render_connected_mesh; }

void RealSenseSharedMemoryPointCloud::set_gpu_connected_mesh(bool p_enabled) {
    if (gpu_connected_mesh == p_enabled) {
        return;
    }
    gpu_connected_mesh = p_enabled;
    set_mesh(Ref<Mesh>());
    grid_width = 0;
    grid_height = 0;
    grid_stride = 0;
}

bool RealSenseSharedMemoryPointCloud::get_gpu_connected_mesh() const { return gpu_connected_mesh; }

void RealSenseSharedMemoryPointCloud::set_cpu_project_points(bool p_enabled) {
    if (cpu_project_points == p_enabled) {
        return;
    }
    cpu_project_points = p_enabled;
    set_mesh(Ref<Mesh>());
    grid_width = 0;
    grid_height = 0;
    grid_stride = 0;
}

bool RealSenseSharedMemoryPointCloud::get_cpu_project_points() const { return cpu_project_points; }

void RealSenseSharedMemoryPointCloud::set_color_enabled(bool p_enabled) {
    if (color_enabled == p_enabled) {
        return;
    }
    color_enabled = p_enabled;
    update_material_params();
    if (cpu_point_material.is_valid()) {
        cpu_point_material->set_shader_parameter("color_enabled", color_enabled);
    }
    if (cpu_project_points || (render_connected_mesh && !gpu_connected_mesh)) {
        set_mesh(Ref<Mesh>());
    }
}

bool RealSenseSharedMemoryPointCloud::get_color_enabled() const { return color_enabled; }

void RealSenseSharedMemoryPointCloud::set_mesh_max_edge(double p_edge) {
    if (Math::is_equal_approx(mesh_max_edge, p_edge)) {
        return;
    }
    mesh_max_edge = p_edge;
    set_mesh(Ref<Mesh>());
}

double RealSenseSharedMemoryPointCloud::get_mesh_max_edge() const { return mesh_max_edge; }

void RealSenseSharedMemoryPointCloud::set_mesh_max_depth_delta(double p_delta) {
    if (Math::is_equal_approx(mesh_max_depth_delta, p_delta)) {
        return;
    }
    mesh_max_depth_delta = p_delta;
    set_mesh(Ref<Mesh>());
}

double RealSenseSharedMemoryPointCloud::get_mesh_max_depth_delta() const { return mesh_max_depth_delta; }

void RealSenseSharedMemoryPointCloud::set_texture_map_mesh(bool p_enabled) {
    if (texture_map_mesh == p_enabled) {
        return;
    }
    texture_map_mesh = p_enabled;
    set_mesh(Ref<Mesh>());
    grid_width = 0;
    grid_height = 0;
    grid_stride = 0;
}

bool RealSenseSharedMemoryPointCloud::get_texture_map_mesh() const { return texture_map_mesh; }

void RealSenseSharedMemoryPointCloud::set_mesh_min_triangle_area(double p_area) {
    if (Math::is_equal_approx(mesh_min_triangle_area, p_area)) {
        return;
    }
    mesh_min_triangle_area = p_area;
    set_mesh(Ref<Mesh>());
}

double RealSenseSharedMemoryPointCloud::get_mesh_min_triangle_area() const { return mesh_min_triangle_area; }

void RealSenseSharedMemoryPointCloud::set_mesh_max_color_delta(double p_delta) {
    if (Math::is_equal_approx(mesh_max_color_delta, p_delta)) {
        return;
    }
    mesh_max_color_delta = p_delta;
    set_mesh(Ref<Mesh>());
}

double RealSenseSharedMemoryPointCloud::get_mesh_max_color_delta() const { return mesh_max_color_delta; }

void RealSenseSharedMemoryPointCloud::set_edge_feather_enabled(bool p_enabled) {
    edge_feather_enabled = p_enabled;
    update_material_params();
}

bool RealSenseSharedMemoryPointCloud::get_edge_feather_enabled() const { return edge_feather_enabled; }

void RealSenseSharedMemoryPointCloud::set_edge_feather_width(double p_width) {
    edge_feather_width = std::max(0.001, p_width);
    update_material_params();
}

double RealSenseSharedMemoryPointCloud::get_edge_feather_width() const { return edge_feather_width; }

void RealSenseSharedMemoryPointCloud::set_edge_feather_min_alpha(double p_alpha) {
    edge_feather_min_alpha = std::max(0.0, std::min(1.0, p_alpha));
    update_material_params();
}

double RealSenseSharedMemoryPointCloud::get_edge_feather_min_alpha() const { return edge_feather_min_alpha; }

void RealSenseSharedMemoryPointCloud::set_delay_enabled(bool p_enabled) {
    delay_enabled = p_enabled;
    if (!delay_enabled) {
        primary_history.clear();
        secondary_history.clear();
    }
}

bool RealSenseSharedMemoryPointCloud::get_delay_enabled() const { return delay_enabled; }

void RealSenseSharedMemoryPointCloud::set_primary_delay_ms(double p_delay_ms) {
    primary_delay_ms = std::max(0.0, p_delay_ms);
    primary_history.clear();
}

double RealSenseSharedMemoryPointCloud::get_primary_delay_ms() const { return primary_delay_ms; }

void RealSenseSharedMemoryPointCloud::set_secondary_delay_ms(double p_delay_ms) {
    secondary_delay_ms = std::max(0.0, p_delay_ms);
    secondary_history.clear();
}

double RealSenseSharedMemoryPointCloud::get_secondary_delay_ms() const { return secondary_delay_ms; }

void RealSenseSharedMemoryPointCloud::set_secondary_shared_memory_name(const String &p_name) {
    if (secondary_shared_memory_name == p_name) {
        return;
    }
    secondary_shared_memory_name = p_name;
    if (secondary_reader.is_null()) {
        secondary_reader.instantiate();
    }
    if (secondary_reader->is_open()) {
        secondary_reader->close();
        secondary_reader->open(secondary_shared_memory_name);
    }
    set_mesh(Ref<Mesh>());
}

String RealSenseSharedMemoryPointCloud::get_secondary_shared_memory_name() const { return secondary_shared_memory_name; }

void RealSenseSharedMemoryPointCloud::set_secondary_enabled(bool p_enabled) {
    if (secondary_enabled == p_enabled) {
        return;
    }
    secondary_enabled = p_enabled;
    set_mesh(Ref<Mesh>());
    grid_width = 0;
    grid_height = 0;
    grid_stride = 0;
}

bool RealSenseSharedMemoryPointCloud::get_secondary_enabled() const { return secondary_enabled; }

void RealSenseSharedMemoryPointCloud::set_secondary_transform(const Transform3D &p_transform) {
    secondary_transform = p_transform;
}

Transform3D RealSenseSharedMemoryPointCloud::get_secondary_transform() const { return secondary_transform; }

bool RealSenseSharedMemoryPointCloud::is_connected() const { return reader.is_valid() && reader->is_open(); }

double RealSenseSharedMemoryPointCloud::get_render_fps() const { return render_fps; }

double RealSenseSharedMemoryPointCloud::get_display_frame_age_ms() const {
    if (last_display_frame_seconds <= 0.0) {
        return 0.0;
    }
    return std::max(0.0, (now_seconds() - last_display_frame_seconds) * 1000.0);
}

int RealSenseSharedMemoryPointCloud::get_last_triangle_count() const { return last_triangle_count; }

int RealSenseSharedMemoryPointCloud::get_last_point_count() const { return last_point_count; }

void RealSenseSharedMemoryPointCloud::ensure_material() {
    const bool want_gpu_mesh = render_connected_mesh && gpu_connected_mesh;
    if (material.is_valid() && material_gpu_mesh_mode == want_gpu_mesh && material_texture_map_mode == texture_map_mesh) {
        return;
    }
    Ref<Shader> shader;
    shader.instantiate();
    const String color_sampler = texture_map_mesh
        ? String("uniform sampler2D color_tex : source_color, filter_nearest;")
        : String("uniform sampler2D color_tex : filter_nearest;");
    String shader_code;
    if (want_gpu_mesh) {
        shader_code = R"(
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D depth_tex : filter_nearest;
__COLOR_TEX_UNIFORM__
uniform vec4 intrinsics = vec4(600.0, 600.0, 320.0, 240.0);
uniform vec2 depth_range = vec2(0.2, 4.5);
uniform bool color_enabled = true;

varying vec2 point_uv;
varying float point_valid;

void vertex() {
    point_uv = UV;
    float depth_m = texture(depth_tex, UV).r;
    point_valid = step(depth_range.x, depth_m) * step(depth_m, depth_range.y);
    vec2 pixel = VERTEX.xy;
    VERTEX = vec3(
        (pixel.x - intrinsics.z) * depth_m / max(0.000001, intrinsics.x),
        -(pixel.y - intrinsics.w) * depth_m / max(0.000001, intrinsics.y),
        -depth_m
    );
}

void fragment() {
    if (point_valid < 0.5) {
        discard;
    }
    float d = texture(depth_tex, point_uv).r;
    if (d < depth_range.x || d > depth_range.y) {
        discard;
    }
    vec4 color = texture(color_tex, point_uv);
    float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    ALBEDO = color_enabled ? color.rgb : vec3(gray);
}
)";
    } else {
        shader_code = R"(
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D depth_tex : filter_nearest;
__COLOR_TEX_UNIFORM__
uniform vec4 intrinsics = vec4(600.0, 600.0, 320.0, 240.0);
uniform vec2 depth_range = vec2(0.2, 4.5);
uniform float point_pixel_size = 2.0;
uniform bool circular_point_splats = false;
uniform bool point_cleanup_enabled = false;
uniform float point_cleanup_depth_delta = 0.06;
uniform float point_cleanup_min_neighbors = 2.0;
uniform vec2 texel_size = vec2(0.01, 0.01);
uniform float max_depth_delta = 0.08;
uniform bool gpu_connected_mesh = false;
uniform bool edge_feather_enabled = false;
uniform float edge_feather_width = 0.035;
uniform float edge_feather_min_alpha = 0.20;
uniform bool color_enabled = true;

varying vec2 point_uv;
varying float point_valid;
varying float point_depth_m;

void vertex() {
    point_uv = UV;
    float depth_m = texture(depth_tex, UV).r;
    point_depth_m = depth_m;
    point_valid = step(depth_range.x, depth_m) * step(depth_m, depth_range.y);
    POINT_SIZE = point_pixel_size;
    vec2 pixel = VERTEX.xy;
    VERTEX = vec3(
        (pixel.x - intrinsics.z) * depth_m / max(0.000001, intrinsics.x),
        -(pixel.y - intrinsics.w) * depth_m / max(0.000001, intrinsics.y),
        -depth_m
    );
}

void fragment() {
    if (point_valid < 0.5) {
        discard;
    }
    if (!gpu_connected_mesh && circular_point_splats && distance(POINT_COORD, vec2(0.5)) > 0.5) {
        discard;
    }
    float d = texture(depth_tex, point_uv).r;
    if (d < depth_range.x || d > depth_range.y) {
        discard;
    }
    float dl = texture(depth_tex, point_uv + vec2(-texel_size.x, 0.0)).r;
    float dr = texture(depth_tex, point_uv + vec2(texel_size.x, 0.0)).r;
    float du = texture(depth_tex, point_uv + vec2(0.0, -texel_size.y)).r;
    float dd = texture(depth_tex, point_uv + vec2(0.0, texel_size.y)).r;
    float close_neighbors = 0.0;
    close_neighbors += (dl >= depth_range.x && dl <= depth_range.y && abs(d - dl) <= point_cleanup_depth_delta) ? 1.0 : 0.0;
    close_neighbors += (dr >= depth_range.x && dr <= depth_range.y && abs(d - dr) <= point_cleanup_depth_delta) ? 1.0 : 0.0;
    close_neighbors += (du >= depth_range.x && du <= depth_range.y && abs(d - du) <= point_cleanup_depth_delta) ? 1.0 : 0.0;
    close_neighbors += (dd >= depth_range.x && dd <= depth_range.y && abs(d - dd) <= point_cleanup_depth_delta) ? 1.0 : 0.0;
    if (point_cleanup_enabled && close_neighbors < point_cleanup_min_neighbors) {
        discard;
    }
    float edge_shade = 1.0;
    if (gpu_connected_mesh) {
        float max_jump = max(max(abs(d - dl), abs(d - dr)), max(abs(d - du), abs(d - dd)));
        if (d < depth_range.x || d > depth_range.y || (max_jump > max_depth_delta && close_neighbors < 2.0)) {
            discard;
        }
        if (edge_feather_enabled) {
            float feather = 1.0 - smoothstep(max_depth_delta - edge_feather_width, max_depth_delta, max_jump);
            edge_shade = mix(edge_feather_min_alpha, 1.0, feather);
        }
    }
    vec4 color = texture(color_tex, point_uv);
    float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    ALBEDO = (color_enabled ? color.rgb : vec3(gray)) * edge_shade;
}
)";
    }
    shader_code = shader_code.replace("__COLOR_TEX_UNIFORM__", color_sampler);
    shader->set_code(shader_code);
    material.instantiate();
    material_gpu_mesh_mode = want_gpu_mesh;
    material_texture_map_mode = texture_map_mesh;
    material->set_shader(shader);
    set_material_override(material);
}

void RealSenseSharedMemoryPointCloud::ensure_vertex_color_material() {
    if (vertex_color_material.is_valid()) {
        return;
    }
    vertex_color_material.instantiate();
    vertex_color_material->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
    vertex_color_material->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
    vertex_color_material->set_cull_mode(BaseMaterial3D::CULL_DISABLED);
}

void RealSenseSharedMemoryPointCloud::ensure_cpu_point_material() {
    if (cpu_point_material.is_valid()) {
        return;
    }
    Ref<Shader> shader;
    shader.instantiate();
    shader->set_code(R"(
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float point_pixel_size = 2.0;
uniform bool circular_point_splats = false;
uniform bool color_enabled = true;

varying vec4 point_color;
varying vec2 point_quad_uv;

void vertex() {
    point_color = COLOR;
    point_quad_uv = UV;
}

void fragment() {
    if (circular_point_splats && distance(point_quad_uv, vec2(0.5)) > 0.5) {
        discard;
    }
    float gray = dot(point_color.rgb, vec3(0.299, 0.587, 0.114));
    ALBEDO = color_enabled ? point_color.rgb : vec3(gray);
}
)");
    cpu_point_material.instantiate();
    cpu_point_material->set_shader(shader);
}

void RealSenseSharedMemoryPointCloud::ensure_texture_material() {
    if (texture_material.is_null()) {
        texture_material.instantiate();
        texture_material->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
        texture_material->set_cull_mode(BaseMaterial3D::CULL_DISABLED);
    }
    if (color_texture.is_valid()) {
        texture_material->set_texture(BaseMaterial3D::TEXTURE_ALBEDO, color_texture);
    }
}

void RealSenseSharedMemoryPointCloud::rebuild_mesh(int p_width, int p_height, int p_stride) {
    grid_width = p_width;
    grid_height = p_height;
    grid_stride = p_stride;

    PackedVector3Array vertices;
    PackedVector2Array uvs;
    PackedVector2Array uv2s;
    PackedColorArray colors;
    PackedInt32Array indices;
    if (render_connected_mesh && gpu_connected_mesh) {
        const int cell_count = (p_width - 1) * (p_height - 1);
        const int vertex_count = cell_count * 6;
        vertices.resize(vertex_count);
        uvs.resize(vertex_count);
        uv2s.resize(vertex_count);
        colors.resize(vertex_count);

        auto pixel_for = [p_width, p_stride](int p_index) -> Vector3 {
            const int y = p_index / p_width;
            const int x = p_index - y * p_width;
            return Vector3(float(x * p_stride), float(y * p_stride), 0.0f);
        };
        auto uv_for = [p_width, p_height](int p_index) -> Vector2 {
            const int y = p_index / p_width;
            const int x = p_index - y * p_width;
            return Vector2((float(x) + 0.5f) / float(p_width), (float(y) + 0.5f) / float(p_height));
        };
        int write_index = 0;
        auto add_tri = [&](int p_a, int p_b, int p_c) {
            const Vector2 uv_a = uv_for(p_a);
            const Vector2 uv_b = uv_for(p_b);
            const Vector2 uv_c = uv_for(p_c);
            const Color tri_data(uv_b.x, uv_b.y, uv_c.x, uv_c.y);
            const int tri_indices[3] = {p_a, p_b, p_c};
            for (int i = 0; i < 3; ++i) {
                const int src_index = tri_indices[i];
                vertices.set(write_index, pixel_for(src_index));
                uvs.set(write_index, uv_for(src_index));
                uv2s.set(write_index, uv_a);
                colors.set(write_index, tri_data);
                write_index++;
            }
        };
        for (int y = 0; y < p_height - 1; y++) {
            for (int x = 0; x < p_width - 1; x++) {
                const int a = y * p_width + x;
                const int b = a + 1;
                const int c = a + p_width;
                const int d = c + 1;
                add_tri(a, c, b);
                add_tri(b, c, d);
            }
        }

        Array arrays;
        arrays.resize(Mesh::ARRAY_MAX);
        arrays[Mesh::ARRAY_VERTEX] = vertices;
        arrays[Mesh::ARRAY_TEX_UV] = uvs;
        arrays[Mesh::ARRAY_TEX_UV2] = uv2s;
        arrays[Mesh::ARRAY_COLOR] = colors;
        Ref<ArrayMesh> mesh;
        mesh.instantiate();
        mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
        ensure_material();
        mesh->surface_set_material(0, material);
        set_mesh(mesh);
        set_material_override(Ref<Material>());
        set_custom_aabb(AABB(Vector3(-100.0, -100.0, -100.0), Vector3(200.0, 200.0, 200.0)));
        return;
    }

    int count = p_width * p_height;
    vertices.resize(count);
    uvs.resize(count);
    int index = 0;
    for (int y = 0; y < p_height; y++) {
        for (int x = 0; x < p_width; x++) {
            vertices.set(index, Vector3(float(x * p_stride), float(y * p_stride), 0.0f));
            uvs.set(index, Vector2((float(x) + 0.5f) / float(p_width), (float(y) + 0.5f) / float(p_height)));
            index++;
        }
    }
    if (render_connected_mesh && gpu_connected_mesh) {
        indices.resize((p_width - 1) * (p_height - 1) * 6);
        int write_index = 0;
        for (int y = 0; y < p_height - 1; y++) {
            for (int x = 0; x < p_width - 1; x++) {
                const int a = y * p_width + x;
                const int b = a + 1;
                const int c = a + p_width;
                const int d = c + 1;
                indices.set(write_index++, a);
                indices.set(write_index++, c);
                indices.set(write_index++, b);
                indices.set(write_index++, b);
                indices.set(write_index++, c);
                indices.set(write_index++, d);
            }
        }
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = vertices;
    arrays[Mesh::ARRAY_TEX_UV] = uvs;
    if (render_connected_mesh && gpu_connected_mesh) {
        arrays[Mesh::ARRAY_INDEX] = indices;
    }
    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    mesh->add_surface_from_arrays((render_connected_mesh && gpu_connected_mesh) ? Mesh::PRIMITIVE_TRIANGLES : Mesh::PRIMITIVE_POINTS, arrays);
    ensure_material();
    mesh->surface_set_material(0, material);
    set_mesh(mesh);
    set_material_override(Ref<Material>());
    set_custom_aabb(AABB(Vector3(-100.0, -100.0, -100.0), Vector3(200.0, 200.0, 200.0)));
}

double RealSenseSharedMemoryPointCloud::now_seconds() const {
    using Clock = std::chrono::steady_clock;
    return std::chrono::duration<double>(Clock::now().time_since_epoch()).count();
}

void RealSenseSharedMemoryPointCloud::push_frame_history(
    std::deque<FrameSnapshot> &p_history,
    const Ref<RealSenseSharedMemoryReader> &p_reader,
    const Ref<Image> &p_depth_image,
    const Ref<Image> &p_color_image
) {
    if (!delay_enabled || p_reader.is_null() || p_depth_image.is_null() || p_color_image.is_null()) {
        return;
    }
    FrameSnapshot frame;
    frame.sequence = p_reader->get_sequence();
    frame.width = p_reader->get_width();
    frame.height = p_reader->get_height();
    frame.stride = p_reader->get_stride();
    frame.intrinsics = p_reader->get_intrinsics();
    frame.depth_image = p_depth_image;
    frame.color_image = p_color_image;
    frame.timestamp_sec = now_seconds();

    if (!p_history.empty() && p_history.back().sequence == frame.sequence) {
        p_history.back() = frame;
    } else {
        p_history.push_back(frame);
    }

    const double max_delay_sec = std::max(primary_delay_ms, secondary_delay_ms) * 0.001 + 2.0;
    while (p_history.size() > 2 && frame.timestamp_sec - p_history.front().timestamp_sec > max_delay_sec) {
        p_history.pop_front();
    }
}

RealSenseSharedMemoryPointCloud::FrameSnapshot RealSenseSharedMemoryPointCloud::select_frame_for_delay(
    const std::deque<FrameSnapshot> &p_history,
    double p_delay_ms,
    const Ref<RealSenseSharedMemoryReader> &p_reader,
    const Ref<Image> &p_depth_image,
    const Ref<Image> &p_color_image
) const {
    if (!delay_enabled || p_delay_ms <= 0.0 || p_history.empty()) {
        FrameSnapshot latest;
        if (p_reader.is_valid()) {
            latest.sequence = p_reader->get_sequence();
            latest.width = p_reader->get_width();
            latest.height = p_reader->get_height();
            latest.stride = p_reader->get_stride();
            latest.intrinsics = p_reader->get_intrinsics();
        }
        latest.depth_image = p_depth_image;
        latest.color_image = p_color_image;
        latest.timestamp_sec = now_seconds();
        return latest;
    }

    const double target_sec = now_seconds() - (p_delay_ms * 0.001);
    const FrameSnapshot *selected = &p_history.front();
    for (const FrameSnapshot &frame : p_history) {
        if (frame.timestamp_sec <= target_sec) {
            selected = &frame;
        } else {
            break;
        }
    }
    return *selected;
}

int RealSenseSharedMemoryPointCloud::rebuild_cpu_connected_mesh(const Ref<Image> &p_depth_image, const Ref<Image> &p_color_image) {
    int width = reader->get_width();
    int height = reader->get_height();
    int stride = reader->get_stride();
    if (width <= 1 || height <= 1) {
        set_mesh(Ref<Mesh>());
        return 0;
    }

    PackedByteArray depth_data = p_depth_image->get_data();
    PackedByteArray color_data = p_color_image->get_data();
    const int cell_count = width * height;
    if (depth_data.size() < cell_count * 4 || color_data.size() < cell_count * 4) {
        set_mesh(Ref<Mesh>());
        return 0;
    }

    Vector4 intrinsics = reader->get_intrinsics();
    const double fx = MAX(0.000001, double(intrinsics.x));
    const double fy = MAX(0.000001, double(intrinsics.y));
    const double ppx = intrinsics.z;
    const double ppy = intrinsics.w;

    PackedInt32Array compact_index;
    compact_index.resize(cell_count);
    for (int i = 0; i < cell_count; ++i) {
        compact_index.set(i, -1);
    }

    PackedVector3Array vertices;
    PackedColorArray colors;
    PackedVector2Array uvs;
    vertices.resize(cell_count);
    colors.resize(cell_count);
    uvs.resize(cell_count);
    int kept_count = 0;
    for (int y = 0; y < height; ++y) {
        const double py = double(y * stride);
        for (int x = 0; x < width; ++x) {
            const int source_index = y * width + x;
            const float depth_m = depth_data.decode_float(source_index * 4);
            if (depth_m < min_depth || depth_m > max_depth) {
                continue;
            }
            const double px = double(x * stride);
            compact_index.set(source_index, kept_count);
            vertices.set(kept_count, Vector3(
                float((px - ppx) * depth_m / fx),
                float(-(py - ppy) * depth_m / fy),
                -depth_m
            ));
            uvs.set(kept_count, Vector2((float(x) + 0.5f) / float(width), (float(y) + 0.5f) / float(height)));
            const int color_offset = source_index * 4;
            colors.set(kept_count, decode_point_color(color_data, color_offset));
            kept_count++;
        }
    }
    vertices.resize(kept_count);
    colors.resize(kept_count);
    uvs.resize(kept_count);
    if (kept_count <= 2) {
        set_mesh(Ref<Mesh>());
        last_point_count = kept_count;
        return 0;
    }

    PackedInt32Array indices;
    indices.resize((width - 1) * (height - 1) * 6);
    const double max_edge_sq = mesh_max_edge * mesh_max_edge;
    int write_index = 0;
    for (int y = 0; y < height - 1; ++y) {
        for (int x = 0; x < width - 1; ++x) {
            const int a = compact_index[y * width + x];
            const int b = compact_index[y * width + x + 1];
            const int c = compact_index[(y + 1) * width + x];
            const int d = compact_index[(y + 1) * width + x + 1];
            const float da = depth_data.decode_float((y * width + x) * 4);
            const float db = depth_data.decode_float((y * width + x + 1) * 4);
            const float dc = depth_data.decode_float(((y + 1) * width + x) * 4);
            const float dd = depth_data.decode_float(((y + 1) * width + x + 1) * 4);
            const bool first_depth_ok = Math::abs(double(da - dc)) <= mesh_max_depth_delta && Math::abs(double(dc - db)) <= mesh_max_depth_delta && Math::abs(double(db - da)) <= mesh_max_depth_delta;
            const bool second_depth_ok = Math::abs(double(db - dc)) <= mesh_max_depth_delta && Math::abs(double(dc - dd)) <= mesh_max_depth_delta && Math::abs(double(dd - db)) <= mesh_max_depth_delta;
            if (a >= 0 && b >= 0 && c >= 0 && first_depth_ok && triangle_valid(vertices, a, c, b, max_edge_sq) && triangle_color_valid(colors, a, c, b)) {
                indices.set(write_index++, a);
                indices.set(write_index++, c);
                indices.set(write_index++, b);
            }
            if (b >= 0 && c >= 0 && d >= 0 && second_depth_ok && triangle_valid(vertices, b, c, d, max_edge_sq) && triangle_color_valid(colors, b, c, d)) {
                indices.set(write_index++, b);
                indices.set(write_index++, c);
                indices.set(write_index++, d);
            }
        }
    }
    indices.resize(write_index);

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = vertices;
    if (texture_map_mesh && color_enabled) {
        arrays[Mesh::ARRAY_TEX_UV] = uvs;
    } else {
        arrays[Mesh::ARRAY_COLOR] = colors;
    }
    arrays[Mesh::ARRAY_INDEX] = indices;
    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    if (texture_map_mesh && color_enabled) {
        if (color_texture.is_null()) {
            color_texture = ImageTexture::create_from_image(p_color_image);
        } else {
            color_texture->update(p_color_image);
        }
        ensure_texture_material();
        mesh->surface_set_material(0, texture_material);
    } else {
        ensure_vertex_color_material();
        mesh->surface_set_material(0, vertex_color_material);
    }
    set_mesh(mesh);
    set_material_override(Ref<Material>());
    set_custom_aabb(AABB(Vector3(-100.0, -100.0, -100.0), Vector3(200.0, 200.0, 200.0)));
    last_point_count = kept_count;
    return write_index / 3;
}

int RealSenseSharedMemoryPointCloud::rebuild_gpu_connected_mesh(const Ref<Image> &p_depth_image) {
    if (reader.is_null() || p_depth_image.is_null()) {
        set_mesh(Ref<Mesh>());
        return 0;
    }
    const int width = reader->get_width();
    const int height = reader->get_height();
    const int stride = reader->get_stride();
    if (width <= 1 || height <= 1) {
        set_mesh(Ref<Mesh>());
        return 0;
    }

    PackedByteArray depth_data = p_depth_image->get_data();
    const int cell_count = width * height;
    if (depth_data.size() < cell_count * 4) {
        set_mesh(Ref<Mesh>());
        return 0;
    }

    Vector4 intrinsics = reader->get_intrinsics();
    const double fx = MAX(0.000001, double(intrinsics.x));
    const double fy = MAX(0.000001, double(intrinsics.y));
    const double ppx = intrinsics.z;
    const double ppy = intrinsics.w;
    const double max_edge_sq = mesh_max_edge * mesh_max_edge;

    if (
        gpu_mesh_cache_width != width
        || gpu_mesh_cache_height != height
        || gpu_mesh_cache_stride != stride
        || gpu_mesh_vertices.size() != cell_count
        || gpu_mesh_uvs.size() != cell_count
    ) {
        gpu_mesh_vertices.resize(cell_count);
        gpu_mesh_uvs.resize(cell_count);
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                const int index = y * width + x;
                gpu_mesh_vertices.set(index, Vector3(float(x * stride), float(y * stride), 0.0f));
                gpu_mesh_uvs.set(index, Vector2((float(x) + 0.5f) / float(width), (float(y) + 0.5f) / float(height)));
            }
        }
        gpu_mesh_cache_width = width;
        gpu_mesh_cache_height = height;
        gpu_mesh_cache_stride = stride;
    }

    auto valid_depth = [&](float p_depth) -> bool {
        return std::isfinite(p_depth) && double(p_depth) >= min_depth && double(p_depth) <= max_depth;
    };
    auto projected = [&](int p_x, int p_y, float p_depth) -> Vector3 {
        const double px = double(p_x * stride);
        const double py = double(p_y * stride);
        return Vector3(
            float((px - ppx) * double(p_depth) / fx),
            float(-(py - ppy) * double(p_depth) / fy),
            -p_depth
        );
    };
    auto edge_ok = [max_edge_sq](const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c) -> bool {
        return p_a.distance_squared_to(p_b) <= max_edge_sq
            && p_b.distance_squared_to(p_c) <= max_edge_sq
            && p_c.distance_squared_to(p_a) <= max_edge_sq;
    };

    PackedInt32Array indices;
    indices.resize((width - 1) * (height - 1) * 6);
    int write_index = 0;
    for (int y = 0; y < height - 1; ++y) {
        for (int x = 0; x < width - 1; ++x) {
            const int ia = y * width + x;
            const int ib = ia + 1;
            const int ic = ia + width;
            const int id = ic + 1;
            const float da = depth_data.decode_float(ia * 4);
            const float db = depth_data.decode_float(ib * 4);
            const float dc = depth_data.decode_float(ic * 4);
            const float dd = depth_data.decode_float(id * 4);
            const bool first_depth_ok = valid_depth(da) && valid_depth(dc) && valid_depth(db)
                && Math::abs(double(da - dc)) <= mesh_max_depth_delta
                && Math::abs(double(dc - db)) <= mesh_max_depth_delta
                && Math::abs(double(db - da)) <= mesh_max_depth_delta;
            if (first_depth_ok) {
                const Vector3 pa = projected(x, y, da);
                const Vector3 pc = projected(x, y + 1, dc);
                const Vector3 pb = projected(x + 1, y, db);
                if (edge_ok(pa, pc, pb)) {
                    indices.set(write_index++, ia);
                    indices.set(write_index++, ic);
                    indices.set(write_index++, ib);
                }
            }
            const bool second_depth_ok = valid_depth(db) && valid_depth(dc) && valid_depth(dd)
                && Math::abs(double(db - dc)) <= mesh_max_depth_delta
                && Math::abs(double(dc - dd)) <= mesh_max_depth_delta
                && Math::abs(double(dd - db)) <= mesh_max_depth_delta;
            if (second_depth_ok) {
                const Vector3 pb = projected(x + 1, y, db);
                const Vector3 pc = projected(x, y + 1, dc);
                const Vector3 pd = projected(x + 1, y + 1, dd);
                if (edge_ok(pb, pc, pd)) {
                    indices.set(write_index++, ib);
                    indices.set(write_index++, ic);
                    indices.set(write_index++, id);
                }
            }
        }
    }
    indices.resize(write_index);

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = gpu_mesh_vertices;
    arrays[Mesh::ARRAY_TEX_UV] = gpu_mesh_uvs;
    arrays[Mesh::ARRAY_INDEX] = indices;
    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    ensure_material();
    mesh->surface_set_material(0, material);
    set_mesh(mesh);
    set_material_override(Ref<Material>());
    set_custom_aabb(AABB(Vector3(-100.0, -100.0, -100.0), Vector3(200.0, 200.0, 200.0)));
    return write_index / 3;
}

int RealSenseSharedMemoryPointCloud::rebuild_cpu_point_cloud(const Ref<Image> &p_depth_image, const Ref<Image> &p_color_image) {
    if (reader.is_null() || p_depth_image.is_null() || p_color_image.is_null()) {
        set_mesh(Ref<Mesh>());
        return 0;
    }
    int width = reader->get_width();
    int height = reader->get_height();
    int stride = reader->get_stride();
    if (width <= 1 || height <= 1) {
        set_mesh(Ref<Mesh>());
        return 0;
    }

    PackedByteArray depth_data = p_depth_image->get_data();
    PackedByteArray color_data = p_color_image->get_data();
    const int cell_count = width * height;
    if (depth_data.size() < cell_count * 4 || color_data.size() < cell_count * 4) {
        set_mesh(Ref<Mesh>());
        return 0;
    }

    Vector4 intrinsics = reader->get_intrinsics();
    const double fx = MAX(0.000001, double(intrinsics.x));
    const double fy = MAX(0.000001, double(intrinsics.y));
    const double ppx = intrinsics.z;
    const double ppy = intrinsics.w;

    PackedVector3Array vertices;
    PackedColorArray colors;
    PackedVector2Array uvs;
    PackedInt32Array indices;
    const int max_vertices = cell_count * 4;
    const int max_indices = cell_count * 6;
    vertices.resize(max_vertices);
    colors.resize(max_vertices);
    uvs.resize(max_vertices);
    indices.resize(max_indices);
    int kept_count = 0;
    int vertex_count = 0;
    int index_count = 0;
    for (int y = 0; y < height; ++y) {
        const double py = double(y * stride);
        for (int x = 0; x < width; ++x) {
            const int source_index = y * width + x;
            const float depth_m = depth_data.decode_float(source_index * 4);
            if (depth_m < min_depth || depth_m > max_depth) {
                continue;
            }
            if (point_cleanup_enabled) {
                int close_neighbors = 0;
                const int nx[4] = { x - 1, x + 1, x, x };
                const int ny[4] = { y, y, y - 1, y + 1 };
                for (int i = 0; i < 4; ++i) {
                    if (nx[i] < 0 || nx[i] >= width || ny[i] < 0 || ny[i] >= height) {
                        continue;
                    }
                    const int neighbor_index = ny[i] * width + nx[i];
                    const float neighbor_depth = depth_data.decode_float(neighbor_index * 4);
                    if (neighbor_depth >= min_depth && neighbor_depth <= max_depth && Math::abs(double(depth_m - neighbor_depth)) <= point_cleanup_depth_delta) {
                        close_neighbors++;
                    }
                }
                if (double(close_neighbors) < point_cleanup_min_neighbors) {
                    continue;
                }
            }
            const double px = double(x * stride);
            const Vector3 point(
                float((px - ppx) * depth_m / fx),
                float(-(py - ppy) * depth_m / fy),
                -depth_m
            );
            const int color_offset = source_index * 4;
            const Color color = decode_point_color(color_data, color_offset);
            const int base = vertex_count;
            const float half_size = float(MAX(0.00025, point_pixel_size * 0.0012 * MAX(0.2, double(depth_m))));
            vertices.set(base + 0, point + Vector3(-half_size, -half_size, 0.0f));
            vertices.set(base + 1, point + Vector3(half_size, -half_size, 0.0f));
            vertices.set(base + 2, point + Vector3(-half_size, half_size, 0.0f));
            vertices.set(base + 3, point + Vector3(half_size, half_size, 0.0f));
            colors.set(base + 0, color);
            colors.set(base + 1, color);
            colors.set(base + 2, color);
            colors.set(base + 3, color);
            uvs.set(base + 0, Vector2(0.0f, 0.0f));
            uvs.set(base + 1, Vector2(1.0f, 0.0f));
            uvs.set(base + 2, Vector2(0.0f, 1.0f));
            uvs.set(base + 3, Vector2(1.0f, 1.0f));
            indices.set(index_count + 0, base + 0);
            indices.set(index_count + 1, base + 2);
            indices.set(index_count + 2, base + 1);
            indices.set(index_count + 3, base + 1);
            indices.set(index_count + 4, base + 2);
            indices.set(index_count + 5, base + 3);
            vertex_count += 4;
            index_count += 6;
            kept_count++;
        }
    }
    vertices.resize(vertex_count);
    colors.resize(vertex_count);
    uvs.resize(vertex_count);
    indices.resize(index_count);
    if (kept_count <= 0) {
        set_mesh(Ref<Mesh>());
        return 0;
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = vertices;
    arrays[Mesh::ARRAY_COLOR] = colors;
    arrays[Mesh::ARRAY_TEX_UV] = uvs;
    arrays[Mesh::ARRAY_INDEX] = indices;
    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    ensure_vertex_color_material();
    mesh->surface_set_material(0, vertex_color_material);
    set_mesh(mesh);
    set_material_override(Ref<Material>());
    set_custom_aabb(AABB(Vector3(-100.0, -100.0, -100.0), Vector3(200.0, 200.0, 200.0)));
    return kept_count;
}

int RealSenseSharedMemoryPointCloud::append_cpu_grid_surface(
    Ref<ArrayMesh> &p_mesh,
    const Ref<RealSenseSharedMemoryReader> &p_reader,
    const Ref<Image> &p_depth_image,
    const Ref<Image> &p_color_image,
    const Transform3D &p_transform,
    int &r_point_count
) {
    if (p_reader.is_null() || p_depth_image.is_null() || p_color_image.is_null()) {
        return 0;
    }
    const int width = p_reader->get_width();
    const int height = p_reader->get_height();
    const int stride = p_reader->get_stride();
    if (width <= 1 || height <= 1) {
        return 0;
    }

    PackedByteArray depth_data = p_depth_image->get_data();
    PackedByteArray color_data = p_color_image->get_data();
    const int cell_count = width * height;
    if (depth_data.size() < cell_count * 4 || color_data.size() < cell_count * 4) {
        return 0;
    }

    Vector4 intrinsics = p_reader->get_intrinsics();
    const double fx = MAX(0.000001, double(intrinsics.x));
    const double fy = MAX(0.000001, double(intrinsics.y));
    const double ppx = intrinsics.z;
    const double ppy = intrinsics.w;

    PackedInt32Array compact_index;
    compact_index.resize(cell_count);
    for (int i = 0; i < cell_count; ++i) {
        compact_index.set(i, -1);
    }

    PackedVector3Array vertices;
    PackedColorArray colors;
    vertices.resize(cell_count);
    colors.resize(cell_count);
    int kept_count = 0;
    for (int y = 0; y < height; ++y) {
        const double py = double(y * stride);
        for (int x = 0; x < width; ++x) {
            const int source_index = y * width + x;
            const float depth_m = depth_data.decode_float(source_index * 4);
            if (depth_m < min_depth || depth_m > max_depth) {
                continue;
            }
            const double px = double(x * stride);
            compact_index.set(source_index, kept_count);
            const Vector3 point(
                float((px - ppx) * depth_m / fx),
                float(-(py - ppy) * depth_m / fy),
                -depth_m
            );
            vertices.set(kept_count, p_transform.xform(point));
            const int color_offset = source_index * 4;
            colors.set(kept_count, decode_point_color(color_data, color_offset));
            kept_count++;
        }
    }
    vertices.resize(kept_count);
    colors.resize(kept_count);
    r_point_count += kept_count;
    if (kept_count <= 2) {
        return 0;
    }

    PackedInt32Array indices;
    indices.resize((width - 1) * (height - 1) * 6);
    const double max_edge_sq = mesh_max_edge * mesh_max_edge;
    int write_index = 0;
    for (int y = 0; y < height - 1; ++y) {
        for (int x = 0; x < width - 1; ++x) {
            const int a = compact_index[y * width + x];
            const int b = compact_index[y * width + x + 1];
            const int c = compact_index[(y + 1) * width + x];
            const int d = compact_index[(y + 1) * width + x + 1];
            const float da = depth_data.decode_float((y * width + x) * 4);
            const float db = depth_data.decode_float((y * width + x + 1) * 4);
            const float dc = depth_data.decode_float(((y + 1) * width + x) * 4);
            const float dd = depth_data.decode_float(((y + 1) * width + x + 1) * 4);
            const bool first_depth_ok = Math::abs(double(da - dc)) <= mesh_max_depth_delta && Math::abs(double(dc - db)) <= mesh_max_depth_delta && Math::abs(double(db - da)) <= mesh_max_depth_delta;
            const bool second_depth_ok = Math::abs(double(db - dc)) <= mesh_max_depth_delta && Math::abs(double(dc - dd)) <= mesh_max_depth_delta && Math::abs(double(dd - db)) <= mesh_max_depth_delta;
            if (a >= 0 && b >= 0 && c >= 0 && first_depth_ok && triangle_valid(vertices, a, c, b, max_edge_sq) && triangle_color_valid(colors, a, c, b)) {
                indices.set(write_index++, a);
                indices.set(write_index++, c);
                indices.set(write_index++, b);
            }
            if (b >= 0 && c >= 0 && d >= 0 && second_depth_ok && triangle_valid(vertices, b, c, d, max_edge_sq) && triangle_color_valid(colors, b, c, d)) {
                indices.set(write_index++, b);
                indices.set(write_index++, c);
                indices.set(write_index++, d);
            }
        }
    }
    indices.resize(write_index);
    if (write_index <= 0) {
        return 0;
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = vertices;
    arrays[Mesh::ARRAY_COLOR] = colors;
    arrays[Mesh::ARRAY_INDEX] = indices;
    p_mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    ensure_vertex_color_material();
    p_mesh->surface_set_material(p_mesh->get_surface_count() - 1, vertex_color_material);
    return write_index / 3;
}

int RealSenseSharedMemoryPointCloud::rebuild_cpu_combined_mesh(const Ref<Image> &p_depth_image, const Ref<Image> &p_color_image) {
    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    int point_count = 0;
    int triangle_count = append_cpu_grid_surface(mesh, reader, p_depth_image, p_color_image, Transform3D(), point_count);

    if (secondary_reader.is_valid() && secondary_reader->is_open()) {
        Ref<Image> secondary_depth_image = secondary_reader->get_depth_image();
        Ref<Image> secondary_color_image = secondary_reader->get_color_image();
        FrameSnapshot secondary_frame = select_frame_for_delay(secondary_history, secondary_delay_ms, secondary_reader, secondary_depth_image, secondary_color_image);
        triangle_count += append_cpu_grid_surface(mesh, secondary_reader, secondary_frame.depth_image, secondary_frame.color_image, secondary_transform, point_count);
    }

    if (mesh->get_surface_count() <= 0) {
        set_mesh(Ref<Mesh>());
        last_point_count = point_count;
        return 0;
    }
    set_mesh(mesh);
    set_material_override(Ref<Material>());
    set_custom_aabb(AABB(Vector3(-100.0, -100.0, -100.0), Vector3(200.0, 200.0, 200.0)));
    last_point_count = point_count;
    return triangle_count;
}

bool RealSenseSharedMemoryPointCloud::triangle_valid(const PackedVector3Array &p_vertices, int p_a, int p_b, int p_c, double p_max_edge_sq) const {
    const Vector3 pa = p_vertices[p_a];
    const Vector3 pb = p_vertices[p_b];
    const Vector3 pc = p_vertices[p_c];
    if (pa.distance_squared_to(pb) > p_max_edge_sq || pb.distance_squared_to(pc) > p_max_edge_sq || pc.distance_squared_to(pa) > p_max_edge_sq) {
        return false;
    }
    if (mesh_min_triangle_area <= 0.0) {
        return true;
    }
    const double area = 0.5 * double((pb - pa).cross(pc - pa).length());
    return area >= mesh_min_triangle_area;
}

bool RealSenseSharedMemoryPointCloud::triangle_color_valid(const PackedColorArray &p_colors, int p_a, int p_b, int p_c) const {
    if (mesh_max_color_delta <= 0.0 || mesh_max_color_delta >= 2.0) {
        return true;
    }
    const Color ca = p_colors[p_a];
    const Color cb = p_colors[p_b];
    const Color cc = p_colors[p_c];
    const Vector3 va(ca.r, ca.g, ca.b);
    const Vector3 vb(cb.r, cb.g, cb.b);
    const Vector3 vc(cc.r, cc.g, cc.b);
    return va.distance_to(vb) <= mesh_max_color_delta && vb.distance_to(vc) <= mesh_max_color_delta && vc.distance_to(va) <= mesh_max_color_delta;
}

Color RealSenseSharedMemoryPointCloud::decode_point_color(const PackedByteArray &p_color_data, int p_color_offset) const {
    const float r = float(uint8_t(p_color_data[p_color_offset])) / 255.0f;
    const float g = float(uint8_t(p_color_data[p_color_offset + 1])) / 255.0f;
    const float b = float(uint8_t(p_color_data[p_color_offset + 2])) / 255.0f;
    const float a = float(uint8_t(p_color_data[p_color_offset + 3])) / 255.0f;
    if (color_enabled) {
        return Color(r, g, b, a);
    }
    const float gray = r * 0.299f + g * 0.587f + b * 0.114f;
    return Color(gray, gray, gray, a);
}

void RealSenseSharedMemoryPointCloud::update_material_params() {
    if (material.is_null()) {
        return;
    }
    if (depth_texture.is_valid()) {
        material->set_shader_parameter("depth_tex", depth_texture);
    }
    if (color_texture.is_valid()) {
        material->set_shader_parameter("color_tex", color_texture);
    }
    material->set_shader_parameter("intrinsics", reader.is_valid() ? reader->get_intrinsics() : Vector4());
    material->set_shader_parameter("depth_range", Vector2(float(min_depth), float(max_depth)));
    material->set_shader_parameter("point_pixel_size", float(point_pixel_size));
    material->set_shader_parameter("circular_point_splats", circular_point_splats);
    material->set_shader_parameter("point_cleanup_enabled", point_cleanup_enabled);
    material->set_shader_parameter("point_cleanup_depth_delta", float(point_cleanup_depth_delta));
    material->set_shader_parameter("point_cleanup_min_neighbors", float(point_cleanup_min_neighbors));
    material->set_shader_parameter("texel_size", Vector2(grid_width > 0 ? 1.0f / float(grid_width) : 1.0f, grid_height > 0 ? 1.0f / float(grid_height) : 1.0f));
    material->set_shader_parameter("max_depth_delta", float(mesh_max_depth_delta));
    material->set_shader_parameter("max_mesh_edge", float(mesh_max_edge));
    material->set_shader_parameter("gpu_connected_mesh", gpu_connected_mesh && render_connected_mesh);
    material->set_shader_parameter("edge_feather_enabled", edge_feather_enabled);
    material->set_shader_parameter("edge_feather_width", float(edge_feather_width));
    material->set_shader_parameter("edge_feather_min_alpha", float(edge_feather_min_alpha));
    material->set_shader_parameter("color_enabled", color_enabled);
}
