#[compute]
#version 460 core

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D splat_core;

layout(std430, set = 0, binding = 1) restrict buffer BucketOffsets {
	uint offsets[65536];
};

layout(r32f, set = 0, binding = 2) restrict writeonly uniform image2D order_image;

layout(set = 0, binding = 3) uniform sampler2D splat_core_secondary;

layout(push_constant) restrict readonly uniform PushConstants {
	vec3 view_direction_local;
	int point_count;
	int core_width;
	float depth_min;
	float depth_scale;
	int order_width;
	int core_width_secondary;
	int primary_point_count;
};

uint depth_bucket(vec3 position) {
	float depth = dot(position, view_direction_local);
	return uint(clamp(
		int((depth - depth_min) * depth_scale),
		0,
		65535
	));
}

void main() {
	uint id = gl_GlobalInvocationID.x;
	if (id >= uint(point_count)) {
		return;
	}
	bool secondary = int(id) >= primary_point_count;
	int resource_id = secondary ? int(id) - primary_point_count : int(id);
	int width = secondary ? core_width_secondary : core_width;
	int texel = resource_id * 3;
	ivec2 address = ivec2(texel % width, texel / width);
	vec3 position = secondary
		? texelFetch(splat_core_secondary, address, 0).xyz
		: texelFetch(splat_core, address, 0).xyz;
	uint sorted_position = atomicAdd(offsets[depth_bucket(position)], 1u);
	ivec2 output_address = ivec2(
		int(sorted_position) % order_width,
		int(sorted_position) / order_width
	);
	imageStore(order_image, output_address, vec4(float(id)));
}
