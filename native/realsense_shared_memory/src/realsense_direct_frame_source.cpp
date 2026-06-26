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
#include <filesystem>
#include <limits>
#include <memory>
#include <string>
#include <vector>

#if defined(REALSENSE_FOUNDATION_STEREO_ENABLED) && defined(_WIN32)
#include <windows.h>
#include <librealsense2/rsutil.h>
#include <onnxruntime/core/session/onnxruntime_c_api.h>
#endif

using namespace godot;

#if defined(REALSENSE_FOUNDATION_STEREO_ENABLED) && defined(_WIN32)
namespace {
struct OrtRuntime {
    HMODULE module = nullptr;
    const OrtApi *api = nullptr;
    OrtEnv *env = nullptr;
    std::wstring dll_dir;

    std::wstring widen(const std::string &p_text) const {
        if (p_text.empty()) {
            return std::wstring();
        }
        int size = MultiByteToWideChar(CP_UTF8, 0, p_text.c_str(), int(p_text.size()), nullptr, 0);
        std::wstring out(size, L'\0');
        MultiByteToWideChar(CP_UTF8, 0, p_text.c_str(), int(p_text.size()), out.data(), size);
        return out;
    }

    bool try_load_from_dir(const std::wstring &p_dir, String &r_error) {
        std::filesystem::path dll_path = p_dir.empty()
            ? std::filesystem::path(L"onnxruntime.dll")
            : std::filesystem::path(p_dir) / L"onnxruntime.dll";
        if (!p_dir.empty() && !std::filesystem::exists(dll_path)) {
            return false;
        }
        if (!p_dir.empty()) {
            AddDllDirectory(p_dir.c_str());
            SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_USER_DIRS);
        }
        module = LoadLibraryW(dll_path.c_str());
        if (!module) {
            r_error = String("LoadLibrary failed for ") + String(std::string(dll_path.u8string()).c_str());
            return false;
        }
        dll_dir = p_dir;
        return true;
    }

    void add_dependency_dir_if_exists(const std::filesystem::path &p_dir) const {
        if (!p_dir.empty() && std::filesystem::is_directory(p_dir)) {
            AddDllDirectory(p_dir.wstring().c_str());
        }
    }

    void add_python_dependency_dirs() const {
        std::vector<std::filesystem::path> roots;
        const wchar_t *appdata = _wgetenv(L"APPDATA");
        if (appdata && appdata[0]) {
            roots.push_back(std::filesystem::path(appdata) / L"Python/Python312/site-packages");
            roots.push_back(std::filesystem::path(appdata) / L"Python/Python311/site-packages");
            roots.push_back(std::filesystem::path(appdata) / L"Python/Python310/site-packages");
        }
        const wchar_t *localappdata = _wgetenv(L"LOCALAPPDATA");
        if (localappdata && localappdata[0]) {
            roots.push_back(std::filesystem::path(localappdata) / L"Programs/Python/Python312/Lib/site-packages");
            roots.push_back(std::filesystem::path(localappdata) / L"Programs/Python/Python311/Lib/site-packages");
            roots.push_back(std::filesystem::path(localappdata) / L"Programs/Python/Python310/Lib/site-packages");
        }
        for (const std::filesystem::path &root : roots) {
            add_dependency_dir_if_exists(root / L"torch/lib");
            add_dependency_dir_if_exists(root / L"tensorrt_libs");
        }
    }

    bool load(String &r_error) {
        if (api && env) {
            return true;
        }
        std::vector<std::wstring> candidates;
        const wchar_t *path_env = _wgetenv(L"ONNXRUNTIME_DLL_DIR");
        if (path_env && path_env[0]) {
            candidates.push_back(path_env);
        }
        const wchar_t *dll_env = _wgetenv(L"ONNXRUNTIME_DLL_PATH");
        if (dll_env && dll_env[0]) {
            std::filesystem::path dll_path(dll_env);
            candidates.push_back(dll_path.parent_path().wstring());
        }
        candidates.push_back(std::filesystem::absolute(L"native/realsense_shared_memory/bin").wstring());
        const wchar_t *appdata = _wgetenv(L"APPDATA");
        if (appdata && appdata[0]) {
            candidates.push_back((std::filesystem::path(appdata) / L"Python/Python312/site-packages/onnxruntime/capi").wstring());
            candidates.push_back((std::filesystem::path(appdata) / L"Python/Python311/site-packages/onnxruntime/capi").wstring());
            candidates.push_back((std::filesystem::path(appdata) / L"Python/Python310/site-packages/onnxruntime/capi").wstring());
        }
        candidates.push_back(L"");
        for (const std::wstring &candidate : candidates) {
            if (try_load_from_dir(candidate, r_error)) {
                break;
            }
        }
        if (!module) {
            r_error = "ONNX Runtime DLL not found. Set ONNXRUNTIME_DLL_DIR to the directory containing onnxruntime.dll.";
            return false;
        }
        add_python_dependency_dirs();
        auto get_api_base = reinterpret_cast<const OrtApiBase *(ORT_API_CALL *)()>(GetProcAddress(module, "OrtGetApiBase"));
        if (!get_api_base) {
            r_error = "ONNX Runtime DLL does not export OrtGetApiBase.";
            return false;
        }
        const OrtApiBase *base = get_api_base();
        api = base->GetApi(ORT_API_VERSION);
        if (!api) {
            r_error = "ONNX Runtime API version mismatch.";
            return false;
        }
        OrtStatus *status = api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "godot_realsense_foundation", &env);
        if (status) {
            r_error = api->GetErrorMessage(status);
            api->ReleaseStatus(status);
            env = nullptr;
            return false;
        }
        return true;
    }
};

OrtRuntime &ort_runtime() {
    static OrtRuntime runtime;
    return runtime;
}

std::string to_utf8(const String &p_value) {
    CharString utf8 = p_value.utf8();
    return std::string(utf8.get_data());
}

std::wstring widen_path(const std::string &p_path) {
    int size = MultiByteToWideChar(CP_UTF8, 0, p_path.c_str(), int(p_path.size()), nullptr, 0);
    std::wstring out(size, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, p_path.c_str(), int(p_path.size()), out.data(), size);
    return out;
}

void release_ort_session(void *&p_session) {
    if (p_session && ort_runtime().api) {
        ort_runtime().api->ReleaseSession(static_cast<OrtSession *>(p_session));
    }
    p_session = nullptr;
}

void release_ort_memory_info(void *&p_memory_info) {
    if (p_memory_info && ort_runtime().api) {
        ort_runtime().api->ReleaseMemoryInfo(static_cast<OrtMemoryInfo *>(p_memory_info));
    }
    p_memory_info = nullptr;
}

bool check_ort(OrtStatus *p_status, String &r_error) {
    if (!p_status) {
        return true;
    }
    const OrtApi *api = ort_runtime().api;
    r_error = api ? String(api->GetErrorMessage(p_status)) : String("ONNX Runtime call failed");
    if (api) {
        api->ReleaseStatus(p_status);
    }
    return false;
}
}
#endif

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
    ClassDB::bind_method(D_METHOD("set_depth_source", "source"), &RealSenseDirectFrameSource::set_depth_source);
    ClassDB::bind_method(D_METHOD("get_depth_source"), &RealSenseDirectFrameSource::get_depth_source);
    ClassDB::bind_method(D_METHOD("set_fast_foundation_backend", "backend"), &RealSenseDirectFrameSource::set_fast_foundation_backend);
    ClassDB::bind_method(D_METHOD("get_fast_foundation_backend"), &RealSenseDirectFrameSource::get_fast_foundation_backend);
    ClassDB::bind_method(D_METHOD("set_fast_foundation_profile", "profile"), &RealSenseDirectFrameSource::set_fast_foundation_profile);
    ClassDB::bind_method(D_METHOD("get_fast_foundation_profile"), &RealSenseDirectFrameSource::get_fast_foundation_profile);
    ClassDB::bind_method(D_METHOD("set_fast_foundation_model_path", "path"), &RealSenseDirectFrameSource::set_fast_foundation_model_path);
    ClassDB::bind_method(D_METHOD("get_fast_foundation_model_path"), &RealSenseDirectFrameSource::get_fast_foundation_model_path);
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
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "depth_source"), "set_depth_source", "get_depth_source");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "fast_foundation_backend"), "set_fast_foundation_backend", "get_fast_foundation_backend");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "fast_foundation_profile"), "set_fast_foundation_profile", "get_fast_foundation_profile");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "fast_foundation_model_path"), "set_fast_foundation_model_path", "get_fast_foundation_model_path");
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
    if (color_output_enabled == p_enabled) {
        return;
    }
    color_output_enabled = p_enabled;
    if (!color_output_enabled) {
        color_image.unref();
    }
#ifdef REALSENSE_DIRECT_ENABLED
    if (opened) {
        close();
        open();
    }
#endif
}

bool RealSenseDirectFrameSource::get_color_output_enabled() const {
    return color_output_enabled;
}

void RealSenseDirectFrameSource::set_depth_source(const String &p_source) {
    String next = p_source.to_lower();
    if (next != "sdk_depth" && next != "fast_foundation_native") {
        next = "sdk_depth";
    }
    if (depth_source == next) {
        return;
    }
    depth_source = next;
    if (opened) {
        close();
        open();
    }
}

String RealSenseDirectFrameSource::get_depth_source() const {
    return depth_source;
}

void RealSenseDirectFrameSource::set_fast_foundation_backend(const String &p_backend) {
    String next = p_backend.to_lower();
    if (next != "onnx_trt" && next != "onnx_cuda" && next != "onnx_cpu") {
        next = "onnx_cuda";
    }
    if (fast_foundation_backend == next) {
        return;
    }
    fast_foundation_backend = next;
#ifdef REALSENSE_DIRECT_ENABLED
    reset_fast_foundation_runtime();
#endif
    if (opened && depth_source == "fast_foundation_native") {
        close();
        open();
    }
}

String RealSenseDirectFrameSource::get_fast_foundation_backend() const {
    return fast_foundation_backend;
}

void RealSenseDirectFrameSource::set_fast_foundation_profile(const String &p_profile) {
    String next = p_profile.to_lower();
    if (next != "full_320x736_i4" && next != "rt_256x512_i2" && next != "fast_192x384_i2") {
        next = "fast_192x384_i2";
    }
    if (fast_foundation_profile == next) {
        return;
    }
    fast_foundation_profile = next;
#ifdef REALSENSE_DIRECT_ENABLED
    reset_fast_foundation_runtime();
#endif
    if (opened && depth_source == "fast_foundation_native") {
        close();
        open();
    }
}

String RealSenseDirectFrameSource::get_fast_foundation_profile() const {
    return fast_foundation_profile;
}

void RealSenseDirectFrameSource::set_fast_foundation_model_path(const String &p_path) {
    if (fast_foundation_model_path == p_path) {
        return;
    }
    fast_foundation_model_path = p_path;
#ifdef REALSENSE_DIRECT_ENABLED
    reset_fast_foundation_runtime();
#endif
    if (opened && depth_source == "fast_foundation_native") {
        close();
        open();
    }
}

String RealSenseDirectFrameSource::get_fast_foundation_model_path() const {
    return fast_foundation_model_path;
}

String RealSenseDirectFrameSource::resolve_fast_foundation_model_path() const {
    if (!fast_foundation_model_path.is_empty()) {
        return fast_foundation_model_path;
    }
    const char *env_path = std::getenv("FAST_FOUNDATIONSTEREO_ONNX");
    if (env_path && env_path[0]) {
        return String(env_path);
    }
    const String base = "experiments/oakd_head_tracker_demo/external/Fast-FoundationStereo/weights/onnx/20_30_48/";
    if (fast_foundation_profile == "full_320x736_i4") {
        return base + String("320x736/20_30_48_iters_4_res_320x736.onnx");
    }
    if (fast_foundation_profile == "rt_256x512_i2") {
        return base + String("256x512/20_30_48_iters_2_res_256x512.onnx");
    }
    return base + String("192x384/20_30_48_iters_2_res_192x384.onnx");
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
    fast_foundation_model_ms = 0.0;
    fast_foundation_pre_ms = 0.0;
    fast_foundation_depth_ms = 0.0;
}

#ifdef REALSENSE_DIRECT_ENABLED
bool RealSenseDirectFrameSource::is_fast_foundation_source() const {
    return depth_source == "fast_foundation_native";
}

void RealSenseDirectFrameSource::reset_fast_foundation_runtime() {
#if defined(REALSENSE_FOUNDATION_STEREO_ENABLED) && defined(_WIN32)
    stop_fast_foundation_worker();
    release_ort_session(fast_foundation_session);
    release_ort_memory_info(fast_foundation_memory_info);
#else
    fast_foundation_session = nullptr;
    fast_foundation_memory_info = nullptr;
#endif
    fast_foundation_loaded = false;
    fast_foundation_input_width = 0;
    fast_foundation_input_height = 0;
    fast_foundation_left_input.clear();
    fast_foundation_right_input.clear();
    fast_foundation_disparity.clear();
    fast_foundation_left_resized.clear();
    fast_foundation_right_resized.clear();
    fast_foundation_applied_sequence = 0;
    fast_foundation_next_job_sequence = 0;
    fast_foundation_pending_ready = false;
    fast_foundation_latest_ready = false;
}

bool RealSenseDirectFrameSource::initialize_fast_foundation_runtime() {
#if defined(REALSENSE_FOUNDATION_STEREO_ENABLED) && defined(_WIN32)
    if (fast_foundation_loaded) {
        return true;
    }
    String error;
    OrtRuntime &runtime = ort_runtime();
    if (!runtime.load(error)) {
        status = String("RealSense native FastFoundation unavailable: ") + error;
        UtilityFunctions::push_warning(status);
        return false;
    }
    const OrtApi *api = runtime.api;
    OrtSessionOptions *options = nullptr;
    if (!check_ort(api->CreateSessionOptions(&options), error)) {
        status = String("RealSense native FastFoundation session options failed: ") + error;
        UtilityFunctions::push_warning(status);
        return false;
    }
    api->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL);
    api->SetSessionLogSeverityLevel(options, 3);
    const std::string backend = to_utf8(fast_foundation_backend);
    fast_foundation_provider_status = "cpu";
    bool trt_provider_attached = false;
    bool cuda_provider_attached = false;
    if (backend == "onnx_trt") {
        OrtTensorRTProviderOptionsV2 *trt_options = nullptr;
        if (!check_ort(api->CreateTensorRTProviderOptions(&trt_options), error)) {
            UtilityFunctions::push_warning(String("RealSense native FastFoundation TensorRT options unavailable: ") + error);
        } else {
            const std::string model_path = to_utf8(resolve_fast_foundation_model_path());
            std::filesystem::path cache_path = std::filesystem::path(model_path).parent_path() / "trt_cache";
            std::filesystem::create_directories(cache_path);
            std::string cache = cache_path.string();
            std::string min_subgraph = "5";
            const char *keys[] = { "trt_fp16_enable", "trt_engine_cache_enable", "trt_engine_cache_path", "trt_min_subgraph_size" };
            const char *values[] = { "1", "1", cache.c_str(), min_subgraph.c_str() };
            check_ort(api->UpdateTensorRTProviderOptions(trt_options, keys, values, 4), error);
            if (!check_ort(api->SessionOptionsAppendExecutionProvider_TensorRT_V2(options, trt_options), error)) {
                UtilityFunctions::push_warning(String("RealSense native FastFoundation TensorRT provider unavailable: ") + error);
            } else {
                trt_provider_attached = true;
            }
            api->ReleaseTensorRTProviderOptions(trt_options);
        }
    }
    if (backend == "onnx_trt" || backend == "onnx_cuda") {
        OrtCUDAProviderOptionsV2 *cuda_options = nullptr;
        if (check_ort(api->CreateCUDAProviderOptions(&cuda_options), error)) {
            if (!check_ort(api->SessionOptionsAppendExecutionProvider_CUDA_V2(options, cuda_options), error)) {
                UtilityFunctions::push_warning(String("RealSense native FastFoundation CUDA provider unavailable: ") + error);
            } else {
                cuda_provider_attached = true;
            }
            api->ReleaseCUDAProviderOptions(cuda_options);
        } else {
            UtilityFunctions::push_warning(String("RealSense native FastFoundation CUDA options unavailable: ") + error);
        }
    }
    if (trt_provider_attached) {
        fast_foundation_provider_status = cuda_provider_attached ? "tensorrt+cuda" : "tensorrt";
    } else if (cuda_provider_attached) {
        fast_foundation_provider_status = "cuda";
    }
    const std::string model_path_utf8 = to_utf8(resolve_fast_foundation_model_path());
    const std::wstring model_path = widen_path(model_path_utf8);
    OrtSession *session = nullptr;
    if (!check_ort(api->CreateSession(runtime.env, model_path.c_str(), options, &session), error)) {
        api->ReleaseSessionOptions(options);
        status = String("RealSense native FastFoundation model load failed: ") + error + " path=" + String(model_path_utf8.c_str());
        UtilityFunctions::push_warning(status);
        return false;
    }
    api->ReleaseSessionOptions(options);

    OrtMemoryInfo *memory_info = nullptr;
    if (!check_ort(api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info), error)) {
        api->ReleaseSession(session);
        status = String("RealSense native FastFoundation memory info failed: ") + error;
        UtilityFunctions::push_warning(status);
        return false;
    }

    OrtTypeInfo *type_info = nullptr;
    const OrtTensorTypeAndShapeInfo *shape_info = nullptr;
    size_t dim_count = 0;
    std::vector<int64_t> dims;
    if (
        check_ort(api->SessionGetInputTypeInfo(session, 0, &type_info), error) &&
        check_ort(api->CastTypeInfoToTensorInfo(type_info, &shape_info), error) &&
        check_ort(api->GetDimensionsCount(shape_info, &dim_count), error)
    ) {
        dims.resize(dim_count);
        if (check_ort(api->GetDimensions(shape_info, dims.data(), dim_count), error) && dim_count >= 4) {
            fast_foundation_input_height = int(dims[2]);
            fast_foundation_input_width = int(dims[3]);
        }
    }
    if (type_info) {
        api->ReleaseTypeInfo(type_info);
    }
    if (fast_foundation_input_width <= 0 || fast_foundation_input_height <= 0) {
        api->ReleaseMemoryInfo(memory_info);
        api->ReleaseSession(session);
        status = "RealSense native FastFoundation model has invalid input shape.";
        UtilityFunctions::push_warning(status);
        return false;
    }
    fast_foundation_session = session;
    fast_foundation_memory_info = memory_info;
    const int input_count = fast_foundation_input_width * fast_foundation_input_height;
    fast_foundation_left_input.assign(size_t(input_count * 3), 0.0f);
    fast_foundation_right_input.assign(size_t(input_count * 3), 0.0f);
    fast_foundation_disparity.assign(size_t(input_count), 0.0f);
    fast_foundation_left_resized.assign(size_t(input_count), 0);
    fast_foundation_right_resized.assign(size_t(input_count), 0);
    fast_foundation_loaded = true;
    UtilityFunctions::print(
        String("RealSense native FastFoundation loaded: backend=") + fast_foundation_backend +
        " provider=" + fast_foundation_provider_status +
        " profile=" + fast_foundation_profile + " input=" + String::num_int64(fast_foundation_input_width) +
        "x" + String::num_int64(fast_foundation_input_height) + " model=" + String(model_path_utf8.c_str())
    );
    return true;
#else
    status = "RealSense native FastFoundation unavailable: extension was built without ONNX Runtime headers.";
    UtilityFunctions::push_warning(status);
    return false;
#endif
}

bool RealSenseDirectFrameSource::open() {
    if (opened) {
        return true;
    }
    clear_frame();
    try {
        reset_post_processing_filters();
        const StreamSettings settings = resolve_stream_settings();
        rs2::config config;
        if (is_fast_foundation_source()) {
            config.enable_stream(RS2_STREAM_INFRARED, 1, settings.depth_width, settings.depth_height, RS2_FORMAT_Y8, settings.depth_fps);
            config.enable_stream(RS2_STREAM_INFRARED, 2, settings.depth_width, settings.depth_height, RS2_FORMAT_Y8, settings.depth_fps);
        } else {
            config.enable_stream(RS2_STREAM_DEPTH, settings.depth_width, settings.depth_height, RS2_FORMAT_Z16, settings.depth_fps);
        }
        if (color_output_enabled) {
            config.enable_stream(RS2_STREAM_COLOR, settings.color_width, settings.color_height, RS2_FORMAT_BGR8, settings.color_fps);
        }
        pipeline_profile = pipeline.start(config);
        if (is_fast_foundation_source()) {
            rs2::video_stream_profile left_profile = pipeline_profile.get_stream(RS2_STREAM_INFRARED, 1).as<rs2::video_stream_profile>();
            rs2::video_stream_profile right_profile = pipeline_profile.get_stream(RS2_STREAM_INFRARED, 2).as<rs2::video_stream_profile>();
            rs2_extrinsics extrinsics = left_profile.get_extrinsics_to(right_profile);
            fast_foundation_baseline_m = std::abs(extrinsics.translation[0]);
            if (fast_foundation_baseline_m <= 0.0001f) {
                throw std::runtime_error("RealSense native FastFoundation needs a valid IR1->IR2 baseline");
            }
            if (!initialize_fast_foundation_runtime()) {
                try {
                    pipeline.stop();
                } catch (...) {
                }
                opened = false;
                return false;
            }
        } else {
            rs2::device device = pipeline_profile.get_device();
            rs2::depth_sensor depth_sensor = device.first<rs2::depth_sensor>();
            depth_scale = depth_sensor.get_depth_scale();
        }
        opened = true;
        status = String("RealSense direct capture active: ") + stream_profile + " source=" + depth_source;
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
    reset_fast_foundation_runtime();
    clear_frame();
    status = "RealSense direct capture is closed";
    UtilityFunctions::print(status);
}

bool RealSenseDirectFrameSource::poll() {
    if (is_fast_foundation_source()) {
        return poll_fast_foundation();
    }
    return poll_sdk_depth();
}

bool RealSenseDirectFrameSource::poll_sdk_depth() {
    if (!opened) {
        return false;
    }
    try {
        rs2::frameset frames;
        if (!pipeline.poll_for_frames(&frames)) {
            return false;
        }
        if (color_output_enabled) {
            frames = align_to_depth.process(frames);
        }
        rs2::depth_frame depth_frame = frames.get_depth_frame();
        rs2::frame color_frame_raw;
        if (color_output_enabled) {
            color_frame_raw = frames.get_color_frame();
        }
        if (!depth_frame || (color_output_enabled && !color_frame_raw)) {
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
        rs2::video_frame color_frame = color_output_enabled ? color_frame_raw.as<rs2::video_frame>() : rs2::video_frame(color_frame_raw);
        const int color_w = color_output_enabled ? color_frame.get_width() : 0;
        const int color_h = color_output_enabled ? color_frame.get_height() : 0;
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
            next_color.resize(color_w * color_h * 4);
        }

        const uint16_t *depth_data = static_cast<const uint16_t *>(depth_frame.get_data());
        float *depth_out = reinterpret_cast<float *>(next_depth.ptrw());
        const uint8_t *color_data = color_output_enabled ? static_cast<const uint8_t *>(color_frame.get_data()) : nullptr;
        uint8_t *color_out = color_output_enabled ? next_color.ptrw() : nullptr;
        const int color_bpp = color_output_enabled ? color_frame.get_bytes_per_pixel() : 0;
        const int color_stride = color_output_enabled ? color_frame.get_stride_in_bytes() : 0;
        const float active_depth_units = depth_frame.get_units();
        int next_valid_depth_pixels = 0;

        if (color_output_enabled) {
            for (int cy = 0; cy < color_h; ++cy) {
                const uint8_t *src_row = color_data + cy * color_stride;
                for (int cx = 0; cx < color_w; ++cx) {
                    const uint8_t *bgr = src_row + cx * color_bpp;
                    const int dst_offset = (cy * color_w + cx) * 4;
                    color_out[dst_offset + 0] = color_bpp >= 3 ? bgr[2] : bgr[0];
                    color_out[dst_offset + 1] = color_bpp >= 2 ? bgr[1] : bgr[0];
                    color_out[dst_offset + 2] = bgr[0];
                    color_out[dst_offset + 3] = 255;
                }
            }
        }

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
            color_image = Image::create_from_data(color_w, color_h, false, Image::FORMAT_RGBA8, next_color);
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

void RealSenseDirectFrameSource::ensure_fast_foundation_worker() {
#if defined(REALSENSE_FOUNDATION_STEREO_ENABLED) && defined(_WIN32)
    if (fast_foundation_worker_running) {
        return;
    }
    fast_foundation_worker_stop = false;
    fast_foundation_pending_ready = false;
    fast_foundation_latest_ready = false;
    fast_foundation_worker_running = true;
    fast_foundation_worker = std::thread(&RealSenseDirectFrameSource::fast_foundation_worker_loop, this);
#endif
}

void RealSenseDirectFrameSource::stop_fast_foundation_worker() {
#if defined(REALSENSE_FOUNDATION_STEREO_ENABLED) && defined(_WIN32)
    {
        std::lock_guard<std::mutex> lock(fast_foundation_mutex);
        fast_foundation_worker_stop = true;
        fast_foundation_pending_ready = false;
    }
    fast_foundation_cv.notify_all();
    if (fast_foundation_worker.joinable()) {
        fast_foundation_worker.join();
    }
    fast_foundation_worker_running = false;
    fast_foundation_worker_stop = false;
    fast_foundation_pending_ready = false;
    fast_foundation_latest_ready = false;
#endif
}

void RealSenseDirectFrameSource::fast_foundation_worker_loop() {
#if defined(REALSENSE_FOUNDATION_STEREO_ENABLED) && defined(_WIN32)
    while (true) {
        FastFoundationJob job;
        {
            std::unique_lock<std::mutex> lock(fast_foundation_mutex);
            fast_foundation_cv.wait(lock, [&]() { return fast_foundation_worker_stop || fast_foundation_pending_ready; });
            if (fast_foundation_worker_stop) {
                return;
            }
            job = std::move(fast_foundation_pending_job);
            fast_foundation_pending_ready = false;
        }

        FastFoundationResult result;
        if (process_fast_foundation_job(job, result)) {
            std::lock_guard<std::mutex> lock(fast_foundation_mutex);
            fast_foundation_latest_result = std::move(result);
            fast_foundation_latest_ready = true;
        }
    }
#endif
}

bool RealSenseDirectFrameSource::process_fast_foundation_job(const FastFoundationJob &p_job, FastFoundationResult &r_result) {
#if defined(REALSENSE_FOUNDATION_STEREO_ENABLED) && defined(_WIN32)
    try {
        const int src_w = p_job.src_width;
        const int src_h = p_job.src_height;
        const int target_w = fast_foundation_input_width;
        const int target_h = fast_foundation_input_height;
        if (src_w <= 0 || src_h <= 0 || target_w <= 0 || target_h <= 0) {
            return false;
        }
        const auto t0 = std::chrono::steady_clock::now();

        std::vector<uint8_t> left_resized(size_t(target_w * target_h));
        std::vector<uint8_t> right_resized(size_t(target_w * target_h));
        auto resize_gray = [](const std::vector<uint8_t> &p_src, int p_src_w, int p_src_h, int p_src_stride, std::vector<uint8_t> &r_dst, int p_dst_w, int p_dst_h) {
            r_dst.resize(size_t(p_dst_w * p_dst_h));
            for (int y = 0; y < p_dst_h; ++y) {
                const int sy = std::min(p_src_h - 1, int((double(y) + 0.5) * double(p_src_h) / double(p_dst_h)));
                const uint8_t *src_row = p_src.data() + sy * p_src_stride;
                uint8_t *dst_row = r_dst.data() + y * p_dst_w;
                for (int x = 0; x < p_dst_w; ++x) {
                    const int sx = std::min(p_src_w - 1, int((double(x) + 0.5) * double(p_src_w) / double(p_dst_w)));
                    dst_row[x] = src_row[sx];
                }
            }
        };
        resize_gray(p_job.left, src_w, src_h, p_job.left_stride, left_resized, target_w, target_h);
        resize_gray(p_job.right, src_w, src_h, p_job.right_stride, right_resized, target_w, target_h);

        std::vector<float> left_input(size_t(target_w * target_h * 3));
        std::vector<float> right_input(size_t(target_w * target_h * 3));
        auto fill_nchw = [](const std::vector<uint8_t> &p_gray, std::vector<float> &r_tensor, int p_w, int p_h) {
            const int pixels = p_w * p_h;
            r_tensor.resize(size_t(pixels * 3));
            const float means[3] = { 0.485f, 0.456f, 0.406f };
            const float inv_stds[3] = { 1.0f / 0.229f, 1.0f / 0.224f, 1.0f / 0.225f };
            for (int i = 0; i < pixels; ++i) {
                const float v = float(p_gray[size_t(i)]) / 255.0f;
                r_tensor[size_t(i)] = (v - means[0]) * inv_stds[0];
                r_tensor[size_t(pixels + i)] = (v - means[1]) * inv_stds[1];
                r_tensor[size_t(pixels * 2 + i)] = (v - means[2]) * inv_stds[2];
            }
        };
        fill_nchw(left_resized, left_input, target_w, target_h);
        fill_nchw(right_resized, right_input, target_w, target_h);
        const auto t_pre = std::chrono::steady_clock::now();

        OrtRuntime &runtime = ort_runtime();
        const OrtApi *api = runtime.api;
        OrtMemoryInfo *memory_info = static_cast<OrtMemoryInfo *>(fast_foundation_memory_info);
        OrtSession *session = static_cast<OrtSession *>(fast_foundation_session);
        if (!api || !memory_info || !session) {
            return false;
        }
        int64_t input_shape[4] = { 1, 3, target_h, target_w };
        OrtValue *left_value = nullptr;
        OrtValue *right_value = nullptr;
        OrtValue *output_value = nullptr;
        String error;
        const size_t input_bytes = left_input.size() * sizeof(float);
        if (!check_ort(api->CreateTensorWithDataAsOrtValue(memory_info, left_input.data(), input_bytes, input_shape, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &left_value), error) ||
            !check_ort(api->CreateTensorWithDataAsOrtValue(memory_info, right_input.data(), input_bytes, input_shape, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &right_value), error)) {
            if (left_value) api->ReleaseValue(left_value);
            if (right_value) api->ReleaseValue(right_value);
            return false;
        }
        const char *input_names[2] = { "left_image", "right_image" };
        const OrtValue *input_values[2] = { left_value, right_value };
        const char *output_names[1] = { "disparity" };
        bool run_ok = check_ort(api->Run(session, nullptr, input_names, input_values, 2, output_names, 1, &output_value), error);
        api->ReleaseValue(left_value);
        api->ReleaseValue(right_value);
        if (!run_ok) {
            return false;
        }
        const auto t_model = std::chrono::steady_clock::now();
        float *output_data = nullptr;
        if (!check_ort(api->GetTensorMutableData(output_value, reinterpret_cast<void **>(&output_data)), error) || !output_data) {
            api->ReleaseValue(output_value);
            return false;
        }
        const int model_pixels = target_w * target_h;
        std::vector<float> disparity(output_data, output_data + model_pixels);
        api->ReleaseValue(output_value);

        const int grid_stride_local = std::max(1, p_job.grid_stride);
        const int grid_w = (src_w + grid_stride_local - 1) / grid_stride_local;
        const int grid_h = (src_h + grid_stride_local - 1) / grid_stride_local;
        std::vector<float> depth(size_t(grid_w * grid_h), 0.0f);
        const double fx_scale = double(target_w) / double(std::max(1, src_w));
        int next_valid_depth_pixels = 0;

        auto sample_disparity = [&](double p_src_x, double p_src_y) -> float {
            const double mx = std::min(double(target_w - 1), std::max(0.0, (p_src_x + 0.5) * double(target_w) / double(src_w) - 0.5));
            const double my = std::min(double(target_h - 1), std::max(0.0, (p_src_y + 0.5) * double(target_h) / double(src_h) - 0.5));
            const int x0 = int(std::floor(mx));
            const int y0 = int(std::floor(my));
            const int x1 = std::min(target_w - 1, x0 + 1);
            const int y1 = std::min(target_h - 1, y0 + 1);
            const float tx = float(mx - double(x0));
            const float ty = float(my - double(y0));
            const float a = disparity[size_t(y0 * target_w + x0)];
            const float b = disparity[size_t(y0 * target_w + x1)];
            const float c = disparity[size_t(y1 * target_w + x0)];
            const float d = disparity[size_t(y1 * target_w + x1)];
            return ((a * (1.0f - tx) + b * tx) * (1.0f - ty) + (c * (1.0f - tx) + d * tx) * ty) / float(std::max(1e-6, fx_scale));
        };

        for (int y = 0; y < grid_h; ++y) {
            const int sy = std::min(y * grid_stride_local, src_h - 1);
            for (int x = 0; x < grid_w; ++x) {
                const int sx = std::min(x * grid_stride_local, src_w - 1);
                const int dst_index = y * grid_w + x;
                const float disp = sample_disparity(double(sx), double(sy));
                float depth_m = 0.0f;
                if (std::isfinite(disp) && disp > 0.75f) {
                    depth_m = float((double(p_job.fx) * double(p_job.baseline_m)) / double(std::max(0.75f, disp)));
                    if (depth_m < 0.05f || depth_m > 10.0f || !std::isfinite(depth_m)) {
                        depth_m = 0.0f;
                    }
                }
                depth[size_t(dst_index)] = depth_m;
                if (depth_m >= p_job.min_depth && depth_m <= p_job.max_depth) {
                    next_valid_depth_pixels++;
                }
            }
        }

        std::vector<uint8_t> color_rgba;
        const int color_w = grid_w;
        const int color_h = grid_h;
        if (p_job.color_enabled) {
            color_rgba.resize(size_t(color_w * color_h * 4));
            if (!p_job.color.empty() && p_job.color_bpp > 0 && p_job.color_stride > 0) {
                auto write_color = [&](int p_dst_index, int p_cx, int p_cy, uint8_t p_alpha) {
                    const int cx = std::min(std::max(0, p_cx), std::max(0, p_job.color_width - 1));
                    const int cy = std::min(std::max(0, p_cy), std::max(0, p_job.color_height - 1));
                    const uint8_t *bgr = p_job.color.data() + cy * p_job.color_stride + cx * p_job.color_bpp;
                    const int dst_offset = p_dst_index * 4;
                    color_rgba[size_t(dst_offset + 0)] = p_job.color_bpp >= 3 ? bgr[2] : bgr[0];
                    color_rgba[size_t(dst_offset + 1)] = p_job.color_bpp >= 2 ? bgr[1] : bgr[0];
                    color_rgba[size_t(dst_offset + 2)] = bgr[0];
                    color_rgba[size_t(dst_offset + 3)] = p_alpha;
                };
                auto write_gray = [&](int p_dst_index, int p_sx, int p_sy, uint8_t p_alpha) {
                    const int sx = std::min(std::max(0, p_sx), std::max(0, src_w - 1));
                    const int sy = std::min(std::max(0, p_sy), std::max(0, src_h - 1));
                    const uint8_t gray = p_job.left[size_t(sy * p_job.left_stride + sx)];
                    const int dst_offset = p_dst_index * 4;
                    color_rgba[size_t(dst_offset + 0)] = gray;
                    color_rgba[size_t(dst_offset + 1)] = gray;
                    color_rgba[size_t(dst_offset + 2)] = gray;
                    color_rgba[size_t(dst_offset + 3)] = p_alpha;
                };

                if (p_job.color_projection_valid) {
                    const int pixel_count = grid_w * grid_h;
                    std::vector<int> projected_x(size_t(pixel_count), -1);
                    std::vector<int> projected_y(size_t(pixel_count), -1);
                    std::vector<float> projected_z(size_t(pixel_count), 0.0f);
                    std::vector<float> nearest_color_z(size_t(p_job.color_width * p_job.color_height), std::numeric_limits<float>::infinity());

                    for (int y = 0; y < grid_h; ++y) {
                        const int sy = std::min(y * grid_stride_local, src_h - 1);
                        for (int x = 0; x < grid_w; ++x) {
                            const int sx = std::min(x * grid_stride_local, src_w - 1);
                            const int dst_index = y * grid_w + x;
                            const float depth_m = depth[size_t(dst_index)];
                            write_gray(dst_index, sx, sy, depth_m > 0.0f ? 255 : 0);
                            if (!(depth_m > 0.0f) || !std::isfinite(depth_m)) {
                                continue;
                            }
                            const float depth_pixel[2] = { float(sx), float(sy) };
                            float depth_point[3] = {};
                            float color_point[3] = {};
                            float color_pixel[2] = {};
                            rs2_deproject_pixel_to_point(depth_point, &p_job.depth_intrinsics, depth_pixel, depth_m);
                            rs2_transform_point_to_point(color_point, &p_job.depth_to_color_extrinsics, depth_point);
                            if (!(color_point[2] > 0.0001f) || !std::isfinite(color_point[2])) {
                                continue;
                            }
                            rs2_project_point_to_pixel(color_pixel, &p_job.color_intrinsics, color_point);
                            const int cx = int(std::lround(color_pixel[0]));
                            const int cy = int(std::lround(color_pixel[1]));
                            if (cx >= 0 && cx < p_job.color_width && cy >= 0 && cy < p_job.color_height) {
                                projected_x[size_t(dst_index)] = cx;
                                projected_y[size_t(dst_index)] = cy;
                                projected_z[size_t(dst_index)] = color_point[2];
                                float &nearest = nearest_color_z[size_t(cy * p_job.color_width + cx)];
                                nearest = std::min(nearest, color_point[2]);
                            }
                        }
                    }

                    constexpr float visibility_tolerance_m = 0.035f;
                    for (int i = 0; i < pixel_count; ++i) {
                        const int cx = projected_x[size_t(i)];
                        const int cy = projected_y[size_t(i)];
                        if (cx < 0 || cy < 0) {
                            continue;
                        }
                        const float nearest = nearest_color_z[size_t(cy * p_job.color_width + cx)];
                        const float z = projected_z[size_t(i)];
                        if (std::isfinite(nearest) && std::abs(z - nearest) <= visibility_tolerance_m) {
                            write_color(i, cx, cy, 255);
                        }
                    }
                } else {
                    for (int y = 0; y < grid_h; ++y) {
                        const int sy = std::min(y * grid_stride_local, src_h - 1);
                        for (int x = 0; x < grid_w; ++x) {
                            const int sx = std::min(x * grid_stride_local, src_w - 1);
                            const int dst_index = y * grid_w + x;
                            const float depth_m = depth[size_t(dst_index)];
                            const int cx = int((double(sx) + 0.5) * double(p_job.color_width) / double(std::max(1, src_w)));
                            const int cy = int((double(sy) + 0.5) * double(p_job.color_height) / double(std::max(1, src_h)));
                            write_color(dst_index, cx, cy, depth_m > 0.0f ? 255 : 0);
                        }
                    }
                }
            } else {
                for (int y = 0; y < grid_h; ++y) {
                    const int sy = std::min(y * grid_stride_local, src_h - 1);
                    const uint8_t *src_row = p_job.left.data() + sy * p_job.left_stride;
                    for (int x = 0; x < grid_w; ++x) {
                        const int sx = std::min(x * grid_stride_local, src_w - 1);
                        const uint8_t gray = src_row[sx];
                        const int dst_offset = (y * color_w + x) * 4;
                        color_rgba[size_t(dst_offset + 0)] = gray;
                        color_rgba[size_t(dst_offset + 1)] = gray;
                        color_rgba[size_t(dst_offset + 2)] = gray;
                        color_rgba[size_t(dst_offset + 3)] = 255;
                    }
                }
            }
        }
        const auto t_depth = std::chrono::steady_clock::now();

        r_result.sequence = p_job.sequence;
        r_result.width = grid_w;
        r_result.height = grid_h;
        r_result.source_width = src_w;
        r_result.source_height = src_h;
        r_result.color_width = p_job.color_enabled ? color_w : 0;
        r_result.color_height = p_job.color_enabled ? color_h : 0;
        r_result.valid_depth_pixels = next_valid_depth_pixels;
        r_result.intrinsics = Vector4(p_job.fx, p_job.fy, p_job.ppx, p_job.ppy);
        r_result.depth = std::move(depth);
        r_result.color = std::move(color_rgba);
        r_result.pre_ms = std::chrono::duration<double, std::milli>(t_pre - t0).count();
        r_result.model_ms = std::chrono::duration<double, std::milli>(t_model - t_pre).count();
        r_result.depth_ms = std::chrono::duration<double, std::milli>(t_depth - t_model).count();
        return true;
    } catch (const std::exception &e) {
        return false;
    }
#else
    return false;
#endif
}

bool RealSenseDirectFrameSource::poll_fast_foundation() {
    if (!opened) {
        return false;
    }
#if defined(REALSENSE_FOUNDATION_STEREO_ENABLED) && defined(_WIN32)
    try {
        if (!initialize_fast_foundation_runtime()) {
            return false;
        }
        rs2::frameset frames;
        if (!pipeline.poll_for_frames(&frames)) {
            return false;
        }
        rs2::video_frame left_frame = frames.get_infrared_frame(1);
        rs2::video_frame right_frame = frames.get_infrared_frame(2);
        rs2::video_frame color_frame = frames.get_color_frame();
        if (!left_frame || !right_frame) {
            return false;
        }

        const int src_w = left_frame.get_width();
        const int src_h = left_frame.get_height();
        if (src_w <= 0 || src_h <= 0 || fast_foundation_input_width <= 0 || fast_foundation_input_height <= 0) {
            return false;
        }
        const uint8_t *left_src = static_cast<const uint8_t *>(left_frame.get_data());
        const uint8_t *right_src = static_cast<const uint8_t *>(right_frame.get_data());
        const int left_stride = left_frame.get_stride_in_bytes();
        const int right_stride = right_frame.get_stride_in_bytes();

        rs2::video_stream_profile left_profile = left_frame.get_profile().as<rs2::video_stream_profile>();
        const rs2_intrinsics rs_intrinsics = left_profile.get_intrinsics();
        ensure_fast_foundation_worker();
        bool should_submit_job = false;
        {
            std::lock_guard<std::mutex> lock(fast_foundation_mutex);
            should_submit_job = !fast_foundation_pending_ready;
        }
        if (should_submit_job) {
            FastFoundationJob job;
            job.sequence = ++fast_foundation_next_job_sequence;
            job.src_width = src_w;
            job.src_height = src_h;
            job.left_stride = left_stride;
            job.right_stride = right_stride;
            job.grid_stride = std::max(1, stride);
            job.fx = rs_intrinsics.fx;
            job.fy = rs_intrinsics.fy;
            job.ppx = rs_intrinsics.ppx;
            job.ppy = rs_intrinsics.ppy;
            job.baseline_m = fast_foundation_baseline_m;
            job.min_depth = filter_min_depth;
            job.max_depth = filter_max_depth;
            job.color_enabled = color_output_enabled;
            job.left.resize(size_t(left_stride * src_h));
            job.right.resize(size_t(right_stride * src_h));
            std::memcpy(job.left.data(), left_src, job.left.size());
            std::memcpy(job.right.data(), right_src, job.right.size());

            if (color_output_enabled && color_frame) {
                job.color_width = color_frame.get_width();
                job.color_height = color_frame.get_height();
                job.color_bpp = color_frame.get_bytes_per_pixel();
                job.color_stride = color_frame.get_stride_in_bytes();
                const wchar_t *project_color_env = _wgetenv(L"REALSENSE_FAST_FOUNDATION_PROJECT_COLOR");
                bool project_color = true;
                if (project_color_env) {
                    project_color = !(
                        project_color_env[0] == L'0' ||
                        project_color_env[0] == L'f' ||
                        project_color_env[0] == L'F' ||
                        project_color_env[0] == L'n' ||
                        project_color_env[0] == L'N'
                    );
                }
                fast_foundation_color_status = project_color ? "project_z" : "resize";
                if (project_color) {
                    rs2::video_stream_profile color_profile = color_frame.get_profile().as<rs2::video_stream_profile>();
                    job.depth_intrinsics = rs_intrinsics;
                    job.color_intrinsics = color_profile.get_intrinsics();
                    job.depth_to_color_extrinsics = left_profile.get_extrinsics_to(color_profile);
                    job.color_projection_valid = true;
                }
                const uint8_t *color_data = static_cast<const uint8_t *>(color_frame.get_data());
                job.color.resize(size_t(job.color_stride * job.color_height));
                std::memcpy(job.color.data(), color_data, job.color.size());
            }

            {
                std::lock_guard<std::mutex> lock(fast_foundation_mutex);
                if (!fast_foundation_pending_ready) {
                    fast_foundation_pending_job = std::move(job);
                    fast_foundation_pending_ready = true;
                } else {
                    should_submit_job = false;
                }
            }
            if (should_submit_job) {
                fast_foundation_cv.notify_one();
            }
        }

        FastFoundationResult result;
        bool have_result = false;
        {
            std::lock_guard<std::mutex> lock(fast_foundation_mutex);
            if (fast_foundation_latest_ready && fast_foundation_latest_result.sequence > fast_foundation_applied_sequence) {
                result = std::move(fast_foundation_latest_result);
                fast_foundation_latest_ready = false;
                fast_foundation_applied_sequence = result.sequence;
                have_result = true;
            }
        }
        if (!have_result) {
            if (depth_image.is_valid()) {
                const double valid_percent = width > 0 && height > 0 ? (100.0 * double(valid_depth_pixels) / double(width * height)) : 0.0;
                status = String("RealSense native FastFoundation active: ") + stream_profile + " backend=" + fast_foundation_backend + " provider=" + fast_foundation_provider_status + " held=1";
                filter_status = String("foundation_native profile=") + fast_foundation_profile
                    + " provider=" + fast_foundation_provider_status
                    + " color=" + fast_foundation_color_status
                    + " input=" + String::num_int64(fast_foundation_input_width) + "x" + String::num_int64(fast_foundation_input_height)
                    + " src=" + String::num_int64(source_width) + "x" + String::num_int64(source_height)
                    + " out=" + String::num_int64(width) + "x" + String::num_int64(height)
                    + " valid=" + String::num_int64(valid_depth_pixels) + "/" + String::num_int64(width * height)
                    + " (" + String::num(valid_percent, 1) + "%)"
                    + " pre=" + String::num(fast_foundation_pre_ms, 1) + "ms"
                    + " model=" + String::num(fast_foundation_model_ms, 1) + "ms"
                    + " depth=" + String::num(fast_foundation_depth_ms, 1) + "ms"
                    + " held=1";
                return false;
            }
            status = String("RealSense native FastFoundation warming: ") + stream_profile + " backend=" + fast_foundation_backend + " provider=" + fast_foundation_provider_status;
            filter_status = String("foundation_native profile=") + fast_foundation_profile
                + " provider=" + fast_foundation_provider_status
                + " color=" + fast_foundation_color_status
                + " input=" + String::num_int64(fast_foundation_input_width) + "x" + String::num_int64(fast_foundation_input_height)
                + " src=" + String::num_int64(src_w) + "x" + String::num_int64(src_h)
                + " waiting_for_worker=1";
            return false;
        }

        PackedByteArray next_depth;
        next_depth.resize(result.depth.size() * sizeof(float));
        if (!result.depth.empty()) {
            std::memcpy(next_depth.ptrw(), result.depth.data(), next_depth.size());
        }
        PackedByteArray next_color;
        if (color_output_enabled && !result.color.empty()) {
            next_color.resize(result.color.size());
            std::memcpy(next_color.ptrw(), result.color.data(), next_color.size());
        }

        intrinsics = result.intrinsics;
        source_width = result.source_width;
        source_height = result.source_height;
        width = result.width;
        height = result.height;
        valid_depth_pixels = result.valid_depth_pixels;
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
        if (color_output_enabled && result.color_width > 0 && result.color_height > 0 && !next_color.is_empty()) {
            color_image = Image::create_from_data(result.color_width, result.color_height, false, Image::FORMAT_RGBA8, next_color);
        } else {
            color_image.unref();
        }
        fast_foundation_pre_ms = result.pre_ms;
        fast_foundation_model_ms = result.model_ms;
        fast_foundation_depth_ms = result.depth_ms;
        const double valid_percent = width > 0 && height > 0 ? (100.0 * double(valid_depth_pixels) / double(width * height)) : 0.0;
        status = String("RealSense native FastFoundation active: ") + stream_profile + " backend=" + fast_foundation_backend + " provider=" + fast_foundation_provider_status;
        filter_status = String("foundation_native profile=") + fast_foundation_profile
            + " provider=" + fast_foundation_provider_status
            + " color=" + fast_foundation_color_status
            + " input=" + String::num_int64(fast_foundation_input_width) + "x" + String::num_int64(fast_foundation_input_height)
            + " src=" + String::num_int64(source_width) + "x" + String::num_int64(source_height)
            + " out=" + String::num_int64(width) + "x" + String::num_int64(height)
            + " valid=" + String::num_int64(valid_depth_pixels) + "/" + String::num_int64(width * height)
            + " (" + String::num(valid_percent, 1) + "%)"
            + " pre=" + String::num(fast_foundation_pre_ms, 1) + "ms"
            + " model=" + String::num(fast_foundation_model_ms, 1) + "ms"
            + " depth=" + String::num(fast_foundation_depth_ms, 1) + "ms";
        return true;
    } catch (const rs2::error &e) {
        status = String("RealSense native FastFoundation poll failed: ") + e.what();
        UtilityFunctions::push_warning(status);
        close();
        return false;
    } catch (const std::exception &e) {
        status = String("RealSense native FastFoundation poll failed: ") + e.what();
        UtilityFunctions::push_warning(status);
        close();
        return false;
    }
#else
    status = "RealSense native FastFoundation unavailable: extension was built without ONNX Runtime support.";
    UtilityFunctions::push_warning(status);
    return false;
#endif
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
