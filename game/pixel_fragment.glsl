#version 430

in vec2 fragTexCoord;
uniform sampler2D texture0;
out vec4 finalColor;

layout(location = 1) uniform int mode;


vec2 uv_klems(vec2 uv, vec2 texture_size) {
    vec2 pixels = uv * texture_size + .5;
    vec2 fl = floor(pixels);
    vec2 fr = fract(pixels);
    vec2 aa = fwidth(pixels) * .75;

    fr = smoothstep( vec2(.5) - aa, vec2(.5) + aa, fr);
    return (fl + fr - .5) / texture_size;
}

vec2 uv_iq( vec2 uv, vec2 texture_size) {
    vec2 pixel = uv * texture_size;

    vec2 seam = floor(pixel + 0.5);
    vec2 dudv = fwidth(pixel);
    pixel = seam + clamp( (pixel - seam) / dudv, -0.5, 0.5);

    return pixel / texture_size;
}

vec2 uv_nearest(vec2 uv, vec2 texture_size) {
    vec2 pixel = uv * texture_size;
    pixel = floor(pixel) + .5;
    return pixel / texture_size;
}

void main(){
    vec2 uv;
    vec2 texture_size = vec2(textureSize(texture0, 0));
    if(mode == 0){
        uv = uv_klems(fragTexCoord, texture_size);
    }
    else if(mode == 1){
        uv = uv_iq(fragTexCoord, texture_size);
    }
    else {
        uv = uv_nearest(fragTexCoord, texture_size);
    }

    finalColor = texture(texture0, uv);
}