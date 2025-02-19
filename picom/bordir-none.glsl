#version 330

in vec2 texcoord;
uniform sampler2D tex;
uniform float corner_radius;
// uniform float time;

// vec4 border_color = vec4(0.659,0.6,0.518, 1.0);
vec4 border_color = vec4(0.157,0.157,0.157, 1.0);
vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec4 default_post_processing(vec4 c);

float distance_to_rounded_corner(vec2 tex_coord, vec2 tex_size, float radius) {
    vec2 corner_distance = min(abs(tex_coord), abs(tex_size - 1 - tex_coord));
    return min(corner_distance.x, corner_distance.y);
    return length(max(corner_distance - vec2(radius), vec2(0)));
}


vec4 add_rounded_corners(
    vec4 win_color,
    vec2 tex_coord,
    vec2 tex_size,
    float radius,
    float thickness
) {
    // vec4 border_color = vec4(hsv2rgb(vec3(
    //     fract(time * 0.001 + dot(tex_coord / vec2(1920, 1080), vec2(1))),
    //     1., 1.
    // )), 1);

    // If we're far from corners, we just pass window texels through
    vec2 corner_distance = min(abs(tex_coord), abs(tex_size - 1 - tex_coord));

    radius -= thickness;

    if (any(greaterThan(corner_distance, vec2(radius)))) {
        // return win_color;
        if (
            any(lessThan(tex_coord, vec2(thickness, thickness)))
                || any(greaterThan(tex_coord, tex_size - vec2(thickness)))
        ) {
            return border_color;
        }
        else {
            // return mix(win_color, border_color, 0.5);
            return win_color;
        }
    }

    // Distance from the closest arc center
    vec2 center_distance = min(
            abs(vec2(radius) - tex_coord),
            abs(vec2(tex_size - radius) - tex_coord)
        );


    // Do some simple anti-aliasing
    float inner_radius = radius - thickness;
    float feather = 1 / inner_radius;
    float r = length(center_distance) / inner_radius;
    float blend = smoothstep(1 - 1/radius, 1, r);
    // float blend = r >= 1 ? 1 : 0;

    // return vec4(vec3(blend
    return mix(win_color, border_color, blend);
}

vec4 window_shader()
{
    vec2 tex_size = textureSize(tex, 0);
    vec4 c = texture2D(tex, texcoord / tex_size, 0);
    vec4 with_corners = add_rounded_corners(c, texcoord, tex_size, corner_radius, 2);
    return default_post_processing(with_corners);
}
