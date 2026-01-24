package game

import "core:math/linalg"
import "core:slice"
import "core:fmt"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

TILEMAP_SIZE :: 16 * 100 * 4
// TILEMAP_SIZE :: 16 * 10

Tile :: i32

GPU_TILEMAP :: true

Tilemap :: struct {
    // thing: bool,
    // bingo_wings: [10]int,
    tiles: [TILEMAP_SIZE * TILEMAP_SIZE]Tile,
    cel_size: int,
    tiles_buffer: u32 `fs:"-"`,

    // used for sending only the data we need to the gpu
    min_cel, max_cel: int,
}

Tileset :: struct {
    texture: rl.Texture,
    count: int,
}

Brush :: struct {
    coordinate: [2]int,
    radius: int
}

tilemap_get_coordinate :: proc(tilemap: ^Tilemap, point: [2]f32) -> [2]int {
    snapped := linalg.floor(point / f32(tilemap.cel_size))
    coordinate := linalg.array_cast(snapped, int)
    coordinate = linalg.clamp(coordinate, [2]int{}, TILEMAP_SIZE)
    return coordinate
}

tilemap_paint :: proc(tilemap: ^Tilemap, brush: Brush, value: Tile){

    cels := tilemap.tiles[:]

    try_paint :: proc(tiles: []i32, cel: int, value: i32) -> bool {
        if cel < 0 || cel >= len(tiles) do return false
        tiles[cel] = value
        return true
    }

    start: int = -brush.radius
    iterations: int = brush.radius * 2 + 1
    for i in 0..<iterations{
        for j in 0..<iterations{
            coord := [2]int { i, j } + start
            float_coord := linalg.array_cast(coord, f32)
            if linalg.length(float_coord) > f32(brush.radius) do continue

            coord += brush.coordinate
            cel := coord.x * TILEMAP_SIZE + coord.y
            if try_paint(cels, cel, value){
                tilemap.min_cel = min(cel, tilemap.min_cel)
                tilemap.max_cel = max(cel, tilemap.max_cel)
            }
        }
    }
}

DRAW_TILESET :: false

make_rect :: proc(position, size: [2]f32) -> rl.Rectangle {
    return { position.x, position.y, size.x, size.y }
}

tilemap_draw_cpu :: proc(tilemap: ^Tilemap, tileset: Tileset, brush: Brush){

    if DRAW_TILESET {
        rl.DrawTextureV(tileset.texture, {}, rl.WHITE)
        return
    }

    tilemap_get_tile :: proc(tilemap: ^Tilemap, coord: [2]int) -> Tile {
        index := coord.x * TILEMAP_SIZE + coord.y
        if index < 0 || index >= len(tilemap.tiles) do return Tile(0)
        return tilemap.tiles[index]
    }

    for i in 0..<TILEMAP_SIZE {
        for j in 0..<TILEMAP_SIZE {
            coordinate := [2]int { i, j }

            neighbors: [4]Tile; {
                neighbors[0] = tilemap_get_tile(tilemap, coordinate)
                neighbors[1] = tilemap_get_tile(tilemap, coordinate + [2]int { 1, 0 })
                neighbors[2] = tilemap_get_tile(tilemap, coordinate + [2]int { 1, 1 })
                neighbors[3] = tilemap_get_tile(tilemap, coordinate + [2]int { 0, 1 })
            }

            match_neighbors :: proc(neighbors: [4]Tile) -> (definition_index: int, rotations: int){
                @(static, rodata) tile_definitions := [6][4]i32 {
                    {0, 0, 0, 0},
                    {0, 0, 0, 1},
                    {0, 0, 1, 1},
                    {0, 1, 0, 1},
                    {1, 0, 1, 1},
                    {1, 1, 1, 1},
                }

                for definition, i in tile_definitions {
                    neighbors := neighbors
                    for j in 0..<len(neighbors){
                        if definition == neighbors {
                            definition_index = i
                            rotations = j
                            return
                        }

                        // rotate
                        old_neighbors := neighbors
                        for k in 0..<len(neighbors){
                            next := (k + 1) % len(neighbors)
                            neighbors[k] = old_neighbors[next]
                        }
                    }
                }
                return
            }

            texture_index, rotations := match_neighbors(neighbors)

            cel_size := f32(tilemap.cel_size)

            // src
            offset := [2]f32 {0, f32(texture_index) * cel_size }
            src_rect := make_rect(offset, cel_size)

            // dst
            dst_position := linalg.array_cast(coordinate, f32) * cel_size
            dst_position += cel_size
            dst_rect := make_rect(dst_position, cel_size)

            // draw
            rl.DrawTexturePro(tileset.texture, src_rect, dst_rect, cel_size / 2., f32(rotations) * 90, rl.WHITE)
        }
    }
}

tilemap_destroy :: proc(tilemap: ^Tilemap){
    rlgl.UnloadShaderBuffer(tilemap.tiles_buffer)
}

tilemap_draw :: proc(tilemap: ^Tilemap, tileset: Tileset, brush: Brush){

    if !GPU_TILEMAP {
        tilemap_draw_cpu(tilemap, tileset, brush)
        return
    }

    tilemap_shader := &state.shaders[.Tilemap]

    if tilemap.tiles_buffer == 0 {
        fmt.println("loading tiles")
        tilemap.tiles_buffer = rlgl.LoadShaderBuffer(len(tilemap.tiles) * size_of(Tile), &tilemap.tiles, rlgl.DYNAMIC_COPY)
    }

    // tile definitions
    {
        tile_definitions := [6][4]i32 {
            {0, 0, 0, 0},
            {0, 0, 0, 1},
            {0, 0, 1, 1},
            {0, 1, 0, 1},
            {1, 0, 1, 1},
            {1, 1, 1, 1},
        }
        definitions_slice := slice.reinterpret([]i32, tile_definitions[:])
        tilemap_shader.uniforms["tile_definitions"] = definitions_slice
    }

    // brush
    tilemap_shader.uniforms["brush_radius"] = i32(brush.radius)
    tilemap_shader.uniforms["brush_coordinate"] = linalg.array_cast(brush.coordinate, i32)

    // tileset
    tilemap_shader.uniforms["tileset_count"] = i32(tileset.count)

    // tilemap
    tilemap_shader.uniforms["tilemap_size"] = i32(TILEMAP_SIZE)
    tilemap_shader.uniforms["cel_size"] = i32(tilemap.cel_size)

    cels_updated := tilemap.max_cel - tilemap.min_cel + 1
    if(cels_updated > 0){
        data_size := u32(size_of(Tile) * cels_updated)
        data_offset := u32(size_of(Tile) * tilemap.min_cel)
        rlgl.UpdateShaderBuffer(tilemap.tiles_buffer, &tilemap.tiles[tilemap.min_cel], data_size, data_offset)
    }

    quad_size :[2]f32 = TILEMAP_SIZE * f32(tilemap.cel_size)
    dest := rl.Rectangle {0, 0, f32(quad_size.x), f32(quad_size.y)}

    if with_shader(tilemap_shader){
        rlgl.BindShaderBuffer(tilemap.tiles_buffer, 0)
        draw_textured_rect(tileset.texture, dest)
    }

    tilemap.min_cel = len(tilemap.tiles) - 1
    tilemap.max_cel = 0
}