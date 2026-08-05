#[compute]
#version 460 core

// Add each block's global base to its 256 local bucket offsets.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict buffer BucketOffsets {
	uint offsets[65536];
};

layout(std430, set = 0, binding = 1) restrict readonly buffer BlockOffsets {
	uint block_offsets[256];
};

void main() {
	uint descending_index = gl_GlobalInvocationID.x;
	uint bucket = 65535u - descending_index;
	offsets[bucket] += block_offsets[gl_WorkGroupID.x];
}
