// Raster ("sticker") backend: sorted-quad hardware rasterizer.
//
// One instanced quad per splat. vertex() reads the splat's position, 3D
// covariance, opacity and DC colour from the index-addressed data texture,
// projects the covariance to a 2D screen-space ellipse, and expands the quad
// along the ellipse's eigen-axes by writing POSITION directly in clip space.
// fragment() evaluates the Gaussian falloff and blends through the standard
// transparent pass with the hardware depth test (no depth-bias params).
//
// The covariance-projection math is a deliberate re-expression of the Compute
// backend's GLSL (render/compute/shaders/gsplat_projection.glsl). The two MUST
// stay in parity; keep this comment in both when either changes.

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, specular_disabled, ambient_light_disabled;

// Core data texture (RGBA32F, 3 texels per splat): position, 3D covariance and
// opacity — floats 0-11 of the frozen AoS struct (see CLAUDE.md). Full float32
// on purpose: covariance entries are sigma^2 and flush to zero in FP16 for any
// splat axis thinner than ~8 mm (see raster_data_textures.gd).
uniform sampler2D splat_core : filter_nearest, repeat_disable;
uniform int core_width = 1;
// SH colour coefficients (RGBA16F, 12 texels per splat): floats 12-59.
uniform sampler2D splat_sh : filter_nearest, repeat_disable;
uniform int sh_width = 1;
// Optional second resource sharing this draw and sorted-order texture. This is
// used for raised surface snow: keeping the data in its own textures avoids a
// second copy of the multi-million-point landscape while still giving both
// resources one global back-to-front splat order.
uniform sampler2D splat_core_secondary : filter_nearest, repeat_disable;
uniform int core_width_secondary = 1;
uniform sampler2D splat_sh_secondary : filter_nearest, repeat_disable;
uniform int sh_width_secondary = 1;
uniform int primary_point_count = 0;
uniform int point_count = 0;
// Optional sorted-order indirection (Phase 3): order_data[sorted_pos] = splat
// index, back-to-front. When use_order is false the order is the identity
// (resource order), which is what the static Phase 2 path renders.
uniform sampler2D order_data : filter_nearest, repeat_disable;
uniform int order_width = 1;
uniform bool use_order = false;
// Procedural Gaussian weather metadata is stored in the two padding floats of
// each splat. Parameters are per weather node, so landscapes retain defaults.
uniform float weather_opacity = 1.0;
uniform float weather_speed = 1.0;
uniform float weather_wind = 0.0;
// World plane equation normal.xyz * position + w. A zero vector disables it;
// positive values are the interior side and are rejected before projection.
uniform vec4 world_clip_plane = vec4(0.0);
// Dynamic outer aperture matching ViewBounds' black-fill rectangle. Rays from
// an interior camera that hit outside the rectangle are rejected before the
// expensive covariance and SH paths. The aperture is bypassed when an editor
// camera orbits to the outdoor side.
uniform vec4 world_aperture_center_enabled = vec4(0.0); // center.xyz, enabled
uniform vec4 world_aperture_axis_x_half_width = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 world_aperture_axis_y_half_height = vec4(0.0, 1.0, 0.0, 0.0);
// Quad half-size in standard deviations; splats fade to ~exp(-0.5 k^2) at the edge.
uniform float quad_extent = 3.0;
uniform float alpha_cutoff = 0.00392; // ~1/255
// AA: the +0.3 covariance dilation (a sub-pixel low-pass) inflates small splats;
// this optionally compensates opacity by sqrt(det_before / det_after) so total
// energy is preserved (Mip-Splatting style). Off by default so the raster output
// stays in parity with the Compute backend (which dilates but does not
// compensate); enable it for slightly cleaner distant/aliased splats.
uniform bool aa_compensation = false;
// Sub-pixel discard: cull splats whose projected diameter is below this many
// pixels (reduces distant shimmer). 0 disables it.
uniform float min_pixel_size = 0.0;

const float SH_C0 = 0.28209479177387814;
const float SH_C1 = 0.4886025119029199;
const float SH_C2_0 = 1.0925484305920792;
const float SH_C2_1 = 1.0925484305920792;
const float SH_C2_2 = 0.31539156525252005;
const float SH_C2_3 = 1.0925484305920792;
const float SH_C2_4 = 0.5462742152960396;
const float SH_C3_0 = 0.5900435899266435;
const float SH_C3_1 = 2.890611442640554;
const float SH_C3_2 = 0.4570457994644658;
const float SH_C3_3 = 0.3731763325901154;
const float SH_C3_4 = 0.4570457994644658;
const float SH_C3_5 = 1.445305721320277;
const float SH_C3_6 = 0.5900435899266435;

const int SPLATS_PER_INSTANCE = 128;
const int CORE_TEXELS_PER_SPLAT = 3;
const int SH_TEXELS_PER_SPLAT = 12;

varying flat vec4 v_color; // rgb + opacity
varying vec2 v_t;          // ellipse-local coordinate in std-dev units

// sRGB -> linear (exact EOTF). SH colours are trained in sRGB space, but on
// Forward+/Mobile this material feeds the scene's linear HDR pipeline, whose
// output encode (linear -> sRGB) must land back on the trained values. Parity
// with srgb_to_linear() in compositor/shaders/gaussian_composite.glsl —
// Compute converts once after blending in sRGB space; here each splat converts
// before the scene's linear blend (same per-splat colour; the blend-space
// difference is inherent to the standard pipeline). PlayCanvas does the same
// per-splat decodeGamma in its gsplatOutput chunk whenever the pipeline is
// linear. Applied in fragment() and skipped when OUTPUT_IS_SRGB (Compatibility
// renders and blends directly in sRGB, matching Compute's accumulation).
vec3 srgb_to_linear(vec3 color) {
	vec3 lower = color / 12.92;
	vec3 higher = pow((color + 0.055) / 1.055, vec3(2.4));
	vec3 cutoff = step(color, vec3(0.04045));
	return mix(higher, lower, cutoff);
}

vec4 fetch_core(int texel, bool secondary) {
	int width = secondary ? core_width_secondary : core_width;
	int x = texel % width;
	int y = texel / width;
	return secondary
		? texelFetch(splat_core_secondary, ivec2(x, y), 0)
		: texelFetch(splat_core, ivec2(x, y), 0);
}

vec4 fetch_sh(int texel, bool secondary) {
	int width = secondary ? sh_width_secondary : sh_width;
	int x = texel % width;
	int y = texel / width;
	return secondary
		? texelFetch(splat_sh_secondary, ivec2(x, y), 0)
		: texelFetch(splat_sh, ivec2(x, y), 0);
}

// Degree-3 spherical-harmonics colour for a view direction. `c` holds the 48
// coefficients (16 basis x RGB, DC first) exactly as laid out in the resource.
// This is a re-expression of get_color() in gsplat_projection.glsl; keep the two
// in parity.
vec3 eval_sh(vec3 view_dir, float c[48]) {
	float x = view_dir.x;
	float y = view_dir.y;
	float z = view_dir.z;
	float xx = x * x, yy = y * y, zz = z * z;
	float xy = x * y, yz = y * z, xz = x * z;
	vec3 rgb = vec3(0.5)
		+ vec3(c[0], c[1], c[2]) * SH_C0
		- vec3(c[3], c[4], c[5]) * SH_C1 * y
		+ vec3(c[6], c[7], c[8]) * SH_C1 * z
		- vec3(c[9], c[10], c[11]) * SH_C1 * x
		+ vec3(c[12], c[13], c[14]) * SH_C2_0 * xy
		- vec3(c[15], c[16], c[17]) * SH_C2_1 * yz
		+ vec3(c[18], c[19], c[20]) * SH_C2_2 * (2.0 * zz - xx - yy)
		- vec3(c[21], c[22], c[23]) * SH_C2_3 * xz
		+ vec3(c[24], c[25], c[26]) * SH_C2_4 * (xx - yy)
		- vec3(c[27], c[28], c[29]) * SH_C3_0 * y * (3.0 * xx - yy)
		+ vec3(c[30], c[31], c[32]) * SH_C3_1 * x * yz
		- vec3(c[33], c[34], c[35]) * SH_C3_2 * y * (4.0 * zz - xx - yy)
		+ vec3(c[36], c[37], c[38]) * SH_C3_3 * z * (2.0 * zz - 3.0 * xx - 3.0 * yy)
		- vec3(c[39], c[40], c[41]) * SH_C3_4 * x * (4.0 * zz - xx - yy)
		+ vec3(c[42], c[43], c[44]) * SH_C3_5 * z * (xx - yy)
		- vec3(c[45], c[46], c[47]) * SH_C3_6 * x * (xx - 3.0 * yy);
	return max(vec3(0.0), rgb);
}

void vertex() {
	// Start culled: NDC (2,2,2) is outside the clip volume, so an unmodified
	// quad is clipped away. The success path at the bottom overwrites POSITION
	// and the varyings; any splat that fails a guard stays culled. (Godot forbids
	// both `return` in vertex() and writing POSITION from a helper, so this is a
	// single nested-guard path.)
	POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	v_color = vec4(0.0);
	v_t = vec2(0.0);

	int local = int(UV.x + 0.5);
	int corner = int(UV.y + 0.5);
	int sorted_pos = INSTANCE_ID * SPLATS_PER_INSTANCE + local;

	if (sorted_pos < point_count) {
		int sidx = sorted_pos;
		if (use_order) {
			int ox = sorted_pos % order_width;
			int oy = sorted_pos / order_width;
			sidx = int(texelFetch(order_data, ivec2(ox, oy), 0).r + 0.5);
		}
		bool secondary = sidx >= primary_point_count;
		int resource_sidx = secondary ? sidx - primary_point_count : sidx;
		int base = resource_sidx * CORE_TEXELS_PER_SPLAT;
		vec4 t0 = fetch_core(base + 0, secondary); // position.xyz, (pad)
		vec4 t1 = fetch_core(base + 1, secondary); // cov xx, xy, xz, yy
		vec4 t2 = fetch_core(base + 2, secondary); // cov yz, zz, opacity, (pad)

		vec3 splat_pos = t0.xyz;
		float weather_seed = t0.w;
		float weather_kind = t2.w;
		bool is_falling_rain = weather_kind > 0.5 && weather_kind < 1.5;
		bool is_falling_snow = weather_kind > 1.5 && weather_kind < 2.5;
		bool is_snow_accumulation = weather_kind > 2.5 && weather_kind < 3.5;
		bool is_weather = weather_kind > 0.5;
		if (is_falling_rain || is_falling_snow) {
			float speed_scale = is_falling_rain ? 0.52 : 0.105;
			float phase = fract(splat_pos.y + 0.5 - TIME * weather_speed * speed_scale);
			splat_pos.y = phase - 0.5;
			float drift_speed = is_falling_rain ? 1.7 : 0.62;
			float drift_scale = is_falling_rain ? 0.022 : 0.070;
			splat_pos.x += sin(TIME * drift_speed + weather_seed * 6.2831853)
				* weather_wind * drift_scale;
		}
		float opacity = clamp(t2.z, 0.0, 1.0);
		if (is_weather) {
			opacity *= max(weather_opacity, 0.0);
			if (is_snow_accumulation) {
				float reveal_progress = clamp(weather_speed, 0.0, 1.0);
				float reveal_softness = max(abs(weather_wind), 0.0001);
				float reveal = 1.0 - smoothstep(
					reveal_progress,
					min(reveal_progress + reveal_softness, 1.0001),
					weather_seed);
				reveal *= step(0.000001, reveal_progress);
				opacity *= reveal;
			}
		}
		mat3 cov3d = mat3(
			vec3(t1.x, t1.y, t1.z),
			vec3(t1.y, t1.w, t2.x),
			vec3(t1.z, t2.x, t2.y));
		vec4 world_pos = MODEL_MATRIX * vec4(splat_pos, 1.0);
		vec4 view_pos = VIEW_MATRIX * world_pos;
		vec4 clip_pos = PROJECTION_MATRIX * view_pos;

		// Godot cameras look down -Z; only splats in front of the camera project.
		bool passes_world_clip = dot(world_clip_plane, world_pos) <= 0.0;
		bool passes_aperture = true;
		if (world_aperture_center_enabled.w > 0.5) {
			vec3 aperture_center = world_aperture_center_enabled.xyz;
			vec3 aperture_x = normalize(world_aperture_axis_x_half_width.xyz);
			vec3 aperture_y = normalize(world_aperture_axis_y_half_height.xyz);
			vec3 aperture_normal = normalize(cross(aperture_x, aperture_y));
			vec3 camera_to_splat = world_pos.xyz - CAMERA_POSITION_WORLD;
			float camera_side = dot(
				aperture_normal,
				CAMERA_POSITION_WORLD - aperture_center);
			float denominator = dot(aperture_normal, camera_to_splat);
			// Only enforce the physical window while the camera is on its
			// interior side. This preserves free outdoor editor navigation.
			if (camera_side > 0.0 && abs(denominator) > 1e-7) {
				float ray_t = -camera_side / denominator;
				vec3 hit = CAMERA_POSITION_WORLD + camera_to_splat * ray_t;
				vec3 hit_delta = hit - aperture_center;
				passes_aperture = ray_t >= 0.0 && ray_t <= 1.0
					&& abs(dot(hit_delta, aperture_x))
						<= world_aperture_axis_x_half_width.w
					&& abs(dot(hit_delta, aperture_y))
						<= world_aperture_axis_y_half_height.w;
			}
		}
		bool in_front = passes_world_clip && passes_aperture
			&& (view_pos.z < -0.0001) && (clip_pos.w > 0.0);
		if (in_front) {
			mat3 object_linear = mat3(MODEL_MATRIX[0].xyz, MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].xyz);
			mat3 world_cov = object_linear * cov3d * transpose(object_linear);

			// --- project 3D covariance to a 2D pixel-space ellipse (parity with compute) ---
			vec2 tan_fov_inv = vec2(PROJECTION_MATRIX[0][0], PROJECTION_MATRIX[1][1]);
			vec2 focal = (VIEWPORT_SIZE - 1.0) * 0.5 * tan_fov_inv;
			vec2 tan_fov = 1.0 / abs(tan_fov_inv);
			float depth_inv = -1.0 / view_pos.z;
			focal *= depth_inv;
			vec2 m = clamp(view_pos.xy * depth_inv, -tan_fov * 1.3, tan_fov * 1.3);
			mat3 view_linear = mat3(VIEW_MATRIX[0].xyz, VIEW_MATRIX[1].xyz, VIEW_MATRIX[2].xyz);
			mat3 jacobian = mat3(
				vec3(focal.x, 0.0, 0.0),
				vec3(0.0, focal.y, 0.0),
				vec3(focal.x * m.x, focal.y * m.y, 0.0));
			mat3 screen_transform = jacobian * view_linear;
			mat3 cov2d_m = screen_transform * world_cov * transpose(screen_transform);
			float det_raw = cov2d_m[0][0] * cov2d_m[1][1] - cov2d_m[0][1] * cov2d_m[0][1];
			vec3 cov2d = vec3(cov2d_m[0][0] + 0.3, cov2d_m[0][1], cov2d_m[1][1] + 0.3);

			float det = cov2d.x * cov2d.z - cov2d.y * cov2d.y;
			if (det > 0.0) {
				// eigenvalues of the symmetric 2x2 [[x, y], [y, z]]
				float mid = 0.5 * (cov2d.x + cov2d.z);
				float disc = sqrt(max(0.0, mid * mid - det));
				float lambda1 = mid + disc;
				float lambda2 = max(mid - disc, 0.0);

				// Sub-pixel discard: cull splats whose undilated projected diameter
				// (geometric mean, 2*det_raw^0.25) is below min_pixel_size.
				if (min_pixel_size <= 0.0 || 2.0 * sqrt(sqrt(max(det_raw, 0.0))) >= min_pixel_size) {
				// eigenvector for lambda1 (major axis); e2 is perpendicular
				vec2 e1;
				if (abs(cov2d.y) < 1e-6) {
					e1 = (cov2d.x >= cov2d.z) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
				} else {
					e1 = normalize(vec2(cov2d.y, lambda1 - cov2d.x));
				}
				vec2 e2 = vec2(-e1.y, e1.x);

				// Clip the quad exactly where the Gaussian tail falls below
				// alpha_cutoff: opacity*exp(-t^2/2) < cutoff <=> t > sqrt(2 ln(opacity/cutoff)).
				// fragment() discards that region anyway, so low-opacity splats get
				// proportionally smaller quads (less overdraw from faint floaters)
				// with zero visible truncation. (A pow(opacity, 0.2)-style shrink is
				// NOT safe here: unlike Compute's 16px-tile coverage rounding, the
				// quad edge is exact, and mid-opacity splats would show hard clipped
				// borders well above the discard threshold.)
				float cutoff = max(alpha_cutoff, 1e-6);
				float ext = min(quad_extent, sqrt(2.0 * log(max(opacity, cutoff) / cutoff)));
				float r1 = ext * sqrt(lambda1);
				float r2 = ext * sqrt(lambda2);

				// corner ids: 0=(-,-) 1=(+,-) 2=(+,+) 3=(-,+)
				vec2 corner_sign = vec2(
					(corner == 1 || corner == 2) ? 1.0 : -1.0,
					(corner >= 2) ? 1.0 : -1.0);

				vec2 pixel_offset = corner_sign.x * r1 * e1 + corner_sign.y * r2 * e2;
				vec2 ndc_offset = pixel_offset * 2.0 / VIEWPORT_SIZE;

				vec4 pos = clip_pos;
				pos.xy += ndc_offset * clip_pos.w;
				POSITION = pos;

				// std-dev coordinate at this corner; interpolates across the quad
				v_t = corner_sign * ext;

				// View-dependent colour from degree-3 SH (the SH texture holds
				// the 48 coefficients contiguously, 12 texels per splat).
				float c[48];
				int sh_base = resource_sidx * SH_TEXELS_PER_SPLAT;
				for (int j = 0; j < 12; j++) {
					vec4 sh_texel = fetch_sh(sh_base + j, secondary);
					c[j * 4 + 0] = sh_texel.x;
					c[j * 4 + 1] = sh_texel.y;
					c[j * 4 + 2] = sh_texel.z;
					c[j * 4 + 3] = sh_texel.w;
				}
				vec3 view_dir = normalize(world_pos.xyz - CAMERA_POSITION_WORLD);
				// AA: preserve energy lost/gained by the 0.3 dilation.
				float eff_opacity = opacity;
				if (aa_compensation) {
					eff_opacity *= sqrt(clamp(det_raw / det, 0.0, 1.0));
				}
				vec3 splat_color = eval_sh(view_dir, c);
				v_color = vec4(splat_color, eff_opacity);
				} // sub-pixel discard guard
			}
		}
	}
}

void fragment() {
	float power = -0.5 * dot(v_t, v_t);
	float a = v_color.a * exp(power);
	if (a < alpha_cutoff) {
		discard;
	}
	vec3 albedo = v_color.rgb;
	if (!OUTPUT_IS_SRGB) {
		albedo = srgb_to_linear(albedo);
	}
	ALBEDO = albedo;
	ALPHA = clamp(a, 0.0, 1.0);
}
