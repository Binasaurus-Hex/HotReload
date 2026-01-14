#version 430

in vec2 fragTexCoord;
in vec3 fragPosition;
out vec4 finalColor;

uniform float zoom = 1.;
uniform float grid_size;

void grid_line(vec2 coord, float block, float thickness, float zoom){
    float alpha = (block / 500) * zoom;
    if(fract(coord.x / block) < (thickness) / block ){
        finalColor = vec4(1, 1, 1, alpha);
    }
    else if(fract(coord.y / block) < (thickness) / block){
        finalColor = vec4(1, 1, 1, alpha);
    }
}

void main(){
    float thickness = 1.2;
    thickness /= zoom;

    finalColor = vec4(.1);

    vec2 centred_position = fragPosition.xy;
    centred_position += vec2(thickness / 2);

    // grid lines
    for(int i = 0; i < 4; i += 1){
        grid_line(centred_position, grid_size * pow(4, float(i)), thickness, zoom);
    }

    // axis
    {
        bool x_axis = centred_position.x < (thickness) && centred_position.x > 0;
        bool y_axis = centred_position.y < (thickness) && centred_position.y > 0;
        if(x_axis){
            finalColor = vec4(1, 0, 0, 8 * zoom);
        }
        if(y_axis){
            finalColor = vec4(0, 1, 0, 8 * zoom);
        }
        if(x_axis && y_axis){
            finalColor = vec4(0, 1, 0, 8 * zoom) + vec4(1, 0, 0, 8 * zoom);
            // finalColor = vec4(1);
        }
    }
}

