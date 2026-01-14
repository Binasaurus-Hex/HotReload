#version 430

in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragPosition;

// input for the actual number of tiles
// assumes a square grid with side length of 'tilemap_size'
layout(std430, binding=0) buffer ssbo0 {
    int tiles[];
};

// tile texture, x = cel_size, y = cel_size * 6
uniform sampler2D texture0;

// 6 tiles, 4 ints per tile defition
// all other tiles are rotations of these basic tiles
uniform int tile_definitions[24];

uniform int brush_radius;
uniform int tilemap_size;
uniform int cel_size;

// should always be 6
uniform int tileset_count;
uniform ivec2 mouse_coord;

out vec4 finalColor;

vec2 rotate_uv_90(vec2 uv, int r){
    uv -= vec2(.5);
    for(int i = 0; i < r; i++){
        uv = vec2(uv.y, -uv.x);
    }
    uv += vec2(.5);
    return uv;
}

vec4 draw_tile(vec2 uv, int tile){
    float offset = float(tile) / float(tileset_count);
    vec2 uv_offset = vec2(0, offset);
    uv = (uv / vec2(1.0f, float(tileset_count))) + uv_offset;
    return texture(texture0, uv);
}

bool coord_is_mouse(ivec2 coordinate){
    return distance(vec2(coordinate), vec2(mouse_coord)) <= brush_radius;
}

int get_tile(ivec2 coordinate){
    if(coord_is_mouse(coordinate)) return 1;
    int index = coordinate.x * tilemap_size + coordinate.y;
    if(index < 0 || index > (tilemap_size * tilemap_size)) return 0;
    return tiles[index];
}

vec4 draw_half_grid(){
    vec2 position = fragPosition.xy;
    ivec2 coordinate = ivec2(round(position / vec2(cel_size)));
    coordinate -= ivec2(1);

    int neighbors_src[4];
    neighbors_src[0] = get_tile(coordinate);
    neighbors_src[1] = get_tile(coordinate + ivec2(1, 0));
    neighbors_src[2] = get_tile(coordinate + ivec2(1, 1));
    neighbors_src[3] = get_tile(coordinate + ivec2(0, 1));

    int texture_index = 0;
    int rotations = 0;
    {
        for(int i = 0; i < tileset_count; i++){

            bool outer_equal = false;
            int neighbors[4] = neighbors_src;
            for(int j = 0; j < 4; j++){

                // check neighbors == tile_definitions[i]
                bool equal = true;
                for(int q = 0; q < 4; q++){
                    if(tile_definitions[i * 4 + q] != neighbors[q]){
                        equal = false;
                        break;
                    }
                }

                if(equal){
                    texture_index = i;
                    rotations = j;
                    outer_equal = true;
                    break;
                }

                // rotate neighbors
                int old_neighbors[4] = neighbors;
                for(int q = 0; q < 4; q++){
                    int next = (q + 1) % 4;
                    neighbors[q] = old_neighbors[next];
                }
            }
            if(outer_equal) break;
        }
    }

    vec2 cel_uv = fract((fragTexCoord * tilemap_size) + .5);
    cel_uv = rotate_uv_90(cel_uv, rotations);
    return draw_tile(cel_uv, texture_index);
}

// #define HALF_GRID

void main(){
    finalColor = draw_half_grid();

    // do mouse highlight
    {
        vec2 position = fragPosition.xy;
        ivec2 coordinate = ivec2(position / vec2(cel_size));
        if(coord_is_mouse(coordinate)){
            finalColor += vec4(.2);
        }

    }
}
