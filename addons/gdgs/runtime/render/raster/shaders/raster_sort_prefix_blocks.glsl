#[compute]
#version 460 core

// Exclusive scans 256 descending buckets per workgroup. Workgroup zero owns
// the farthest bucket range, so block_sums are already in draw order.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict readonly buffer BucketCounts {
	uint counts[65536];
};

layout(std430, set = 0, binding = 1) restrict writeonly buffer BucketOffsets {
	uint offsets[65536];
};

layout(std430, set = 0, binding = 2) restrict writeonly buffer BlockSums {
	uint block_sums[256];
};

shared uint scan_values[256];

void main() {
	uint local_index = gl_LocalInvocationID.x;
	uint descending_index = gl_WorkGroupID.x * 256u + local_index;
	uint bucket = 65535u - descending_index;
	uint own_count = counts[bucket];
	scan_values[local_index] = own_count;
	barrier();

	for (uint stride = 1u; stride < 256u; stride <<= 1u) {
		uint addend = local_index >= stride
			? scan_values[local_index - stride]
			: 0u;
		barrier();
		scan_values[local_index] += addend;
		barrier();
	}

	offsets[bucket] = scan_values[local_index] - own_count;
	if (local_index == 255u) {
		block_sums[gl_WorkGroupID.x] = scan_values[local_index];
	}
}
