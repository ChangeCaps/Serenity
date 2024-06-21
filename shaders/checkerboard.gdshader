shader_type spatial;

uniform float scale;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	vec2 uv = floor(UV * scale);
	ivec2 iuv = ivec2(uv);
	
	bool is_black = (iuv.x + iuv.y) % 2 == 0;
	
	if (is_black) {
		ALBEDO = vec3(0.0, 0.0, 0.0);
	} else {
		ALBEDO = vec3(1.0, 1.0, 1.0);
	}
}