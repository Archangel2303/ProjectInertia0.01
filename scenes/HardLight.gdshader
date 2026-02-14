shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

// =====================
// Color / Overall Look
// =====================
uniform vec4 construct_color : source_color = vec4(1.0, 0.35, 0.05, 1.0);
uniform float construct_amount = 1.0;        // 0..1 (fade effect on/off)
uniform float emission_strength = 10;      // overall glow multiplier
uniform bool use_procedural_hex = true;

uniform float hex_scale = 12.0;        // bigger = smaller hexes
uniform float hex_line_width = 0.05;   // thickness of hex lines
uniform float hex_softness = 0.02;     // edge softness (anti-alias feel)
uniform float hex_strength = 0.18;     // how much the hex contributes to glow
uniform float hex_scroll_speed = 0.03; // subtle drift like projection
// =====================
// Rim (edge) shaping
// =====================
uniform float rim_power = 4.5;               // higher = thinner edge band
uniform float rim_strength = 2.2;            // adds edge glow

// Alpha: center more transparent, edges more opaque
uniform float alpha_center = 0.022;           // interior transparency
uniform float alpha_edge   = .85;           // edge opacity

// Color intensity at edges
uniform float edge_color_boost = 1.2;

// =====================
// Swirl / internal energy
// =====================
uniform float noise_scale = 3.2;
uniform float swirl_speed = 0.65;
uniform float swirl_strength = 0.6;

// =====================
// Optional pattern overlay (hex/wire)
// Assign a tiling grayscale texture in Shader Params -> pattern_tex
// =====================
uniform sampler2D pattern_tex : source_color;
uniform float pattern_scale = 6.0;
uniform float pattern_strength = 0.35;

// =====================
// Projection pulse (SOFT traveling energy wave)
// No on/off strobing: always has baseline energy.
// =====================
uniform float pulse_speed = 0.6;             // how fast the wave moves
uniform float pulse_frequency = 0.75;         // repeats along the mesh (UV space)
uniform float pulse_strength = 0.95;          // how much it boosts glow
uniform float pulse_baseline = 0.35;         // 0..1 baseline energy (never "off")

// Optional "projector" shimmer
uniform float scanline_strength = 0.25;      // 0..0.25 recommended
uniform float scanline_density = 320.0;      // higher = tighter lines
uniform float flicker_strength = 0.07;       // subtle flicker

// ---------------------
// Cheap hash / noise
// ---------------------
float hash(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float n000 = hash(i + vec3(0.0,0.0,0.0));
    float n100 = hash(i + vec3(1.0,0.0,0.0));
    float n010 = hash(i + vec3(0.0,1.0,0.0));
    float n110 = hash(i + vec3(1.0,1.0,0.0));
    float n001 = hash(i + vec3(0.0,0.0,1.0));
    float n101 = hash(i + vec3(1.0,0.0,1.0));
    float n011 = hash(i + vec3(0.0,1.0,1.0));
    float n111 = hash(i + vec3(1.0,1.0,1.0));

    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);

    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);

    return mix(nxy0, nxy1, f.z);
}
// Returns distance to nearest hex edge in a hex tiling (0 at edge, >0 inside cell)
float hex_edge_dist(vec2 p) {
    // Pointy-top hex axial-ish transform
    // Based on mapping to hex coordinates then computing distance to edges.
    const vec2 k = vec2(1.0, 1.7320508); // (1, sqrt(3))
    p.x = 2.0 / 3.0;

    // Convert to "skewed" grid space
    vec2 a = vec2(p.x, (p.y + p.x) / k.y);
    vec2 b = vec2(p.x, (p.y - p.x) / k.y);

    // Find nearest cell centers for the two interleaved lattices
    vec2 ai = floor(a + 0.5);
    vec2 bi = floor(b + 0.5);

    // Reconstruct candidate centers back to p-space
    vec2 ca = vec2(ai.x, (ai.y * k.y) - ai.x);
    vec2 cb = vec2(bi.x, (bi.y * k.y) + bi.x);
    ca.x = 1.5;
    cb.x= 1.5;

    // Choose closer center
    vec2 da = p - ca;
    vec2 db = p - cb;
    vec2 d  = (dot(da, da) < dot(db, db)) ? da : db;

    // Distance to hex boundary for a unit-ish hex
    d = abs(d);
    float m = max(d.x * 0.8660254 + d.y * 0.5, d.y); // 0.866 = cos(30), 0.5 = sin(30)
    return m;
}

// Produces a hex line mask: 1 on lines, 0 off lines
float hex_lines(vec2 uv, float scale, float line_width, float soft) {
    vec2 p = uv * scale;

    // distance to nearest hex edge; the "unit" boundary is around ~0.5
    float dist = hex_edge_dist(p);

    // Put the line around the boundary value
    float boundary = 0.5;
    float d = abs(dist - boundary);

    // Anti-aliased-ish line
    float line = 1.0 - smoothstep(line_width, line_width + soft, d);
    return clamp(line, 0.0, 1.0);
}
void fragment() {
    // ---------------------
    // Rim / Fresnel (0 center -> 1 edges)
    // ---------------------
    float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    float rim = pow(1.0 - ndv, rim_power);
    float rim_mask = smoothstep(0.0, 1.0, rim);

    // ---------------------
    // Swirl energy (cheap, stable)
    // ---------------------
    vec3 p = vec3(UV, 0.0) * noise_scale;
    p.xy += vec2(TIME * swirl_speed, TIME * swirl_speed * 0.7);

    float n1 = noise3(p);
    float n2 = noise3(p * 2.1 + 13.7);
    float swirl = mix(n1, n2, 0.5);
    swirl = smoothstep(0.25, 0.85, swirl) * swirl_strength;

    // ---------------------
    // Optional pattern overlay (hex/wire)
    // ---------------------
    
    
float pat = 0.0;

if (use_procedural_hex) {
    vec2 huv = UV + vec2(TIME * hex_scroll_speed, TIME * hex_scroll_speed * 0.6);
    float h = hex_lines(huv, hex_scale, hex_line_width, hex_softness);
    pat = h * hex_strength;
} else {
    // Keep your texture option if you ever want it
    pat = texture(pattern_tex, UV * pattern_scale + vec2(TIME * 0.05, TIME * 0.03)).r;
    pat = smoothstep(0.4, 0.9, pat) * pattern_strength;
}
    // ---------------------
    // SOFT projection wave (no strobe)
    // pulse_raw: 0..1 smooth wave along UV.y that moves over time
    // pulse: remapped to [pulse_baseline..1]
    // ---------------------
    float x = UV.y * pulse_frequency + TIME * pulse_speed;
    float pulse_raw = 0.5 + 0.5 * sin(6.2831853 * x);     // 0..1
    pulse_raw = smoothstep(0.20, 0.90, pulse_raw);        // soften peaks/valleys
    float pulse = mix(pulse_baseline, 1.0, pulse_raw);    // never fully off

    // How much above baseline we are (0..1-ish)
    float pulse_delta = max(pulse - pulse_baseline, 0.0);

    // ---------------------
    // Projector shimmer (subtle)
    // ---------------------
    float scan = 1.0;
    if (scanline_strength > 0.0) {
        scan = 1.0 - scanline_strength + scanline_strength * (0.5 + 0.5 * sin(UV.y * scanline_density + TIME * 6.0));
    }

    float flicker = 1.0;
    if (flicker_strength > 0.0) {
        flicker = 1.0 - flicker_strength + flicker_strength * (0.5 + 0.5 * sin(TIME * 18.0));
    }

    // ---------------------
    // Combine glow drivers
    // ---------------------
    float glow = (rim_mask * rim_strength) + swirl + pat;

    // Pulse should affect EMISSION more than ALPHA (to avoid "on/off" look)
    float pulse_boost = 1.0 + pulse_delta * pulse_strength;

    // Apply pulse + shimmer primarily to glow
    glow *= pulse_boost * scan * flicker;

    // ---------------------
    // Color shaping
    // More intense near edges, slightly brighter when pulse passes
    // ---------------------
    vec3 core_color = vec3(1.0, 0.32, 0.05);   // strong orange
vec3 edge_color = vec3(.95, 0.18, 0.02);   // deep red orange
vec3 col = mix(core_color, edge_color, rim_mask);
    col *= mix(1.0, edge_color_boost, rim_mask);
    col *= (1.0 + pulse_delta * (pulse_strength * 0.35));

    // ---------------------
    // Outputs
    // ---------------------
    ALBEDO = col * 0.15;

    // Emission drives the neon glow (best with WorldEnvironment Glow enabled)
	float core = 0.25; // baseline energy everywhere
    EMISSION = col * (core + glow) * emission_strength * construct_amount *(1.0 + rim_mask * 1.0);

    // Alpha fades to center; only a tiny pulse influence (avoid strobing)
    float rim_alpha = pow(rim_mask, 1.6); //stronger edge bias
    float base_alpha = mix(alpha_center, alpha_edge, rim_alpha); // subtle, not dramatic
    ALPHA = clamp(base_alpha, 0.0, 1.0) * construct_amount;

    ROUGHNESS = 0.12;
    METALLIC = 0.0;
}