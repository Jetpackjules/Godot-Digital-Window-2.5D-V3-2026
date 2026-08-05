#[compute]
#version 460 core

// Exclusive scan of the 256 block totals.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict readonly buffer BlockSums {
	uint block_sums[256];
};

layout(std430, set = 0, binding = 1) restrict writeonly buffer BlockOffsets {
	uint block_offsets[256];
};

shared uint scan_values[256];

void main() {
	uint index = gl_LocalInvocationID.x;
	uint own_sum = block_sums[index];
	scan_values[index] = own_sum;
	barrier();

	for (uint stride = 1u; stride < 256u; stride <<= 1u) {
		uint addend = index >= stride ? scan_values[index - stride] : 0u;
		barrier();
		scan_values[index] += addend;
		barrier();
	}
	block_offsets[index] = scan_values[index] - own_sum;
}
