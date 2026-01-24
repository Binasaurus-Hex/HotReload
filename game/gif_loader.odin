package game

import "core:fmt"
import "core:slice"
import sa "core:container/small_array"
import rl "vendor:raylib"

peek_bytes :: proc(s: []byte, count: int) -> []byte {
    a, _ := slice.split_at(s, count)
    return a
}

eat_bytes :: proc(s: ^[]byte, count: int) -> []byte {
    a, b := slice.split_at(s^, count)
    s^ = b
    return a
}

eat_type :: proc(s: ^[]byte, $T: typeid) -> ^T {
    raw := eat_bytes(s, size_of(T))
    return transmute(^T)&raw[0]
}

eat_slice :: proc(s: ^[]byte, $T: typeid, count: int) -> []T {
    raw := eat_bytes(s, size_of(T) * count)
    return slice.reinterpret([]T, raw)
}

example_gif := []byte {
    0x47,
    0x49,
    0x46,
    0x38,
    0x39,
    0x61,
    0x0A,
    0x00,
    0x0A,
    0x00,
    0x91,
    0x00,
    0x00,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0x00,
    0x00,
    0x00,
    0x00,
    0xFF,
    0x00,
    0x00,
    0x00,
    0x21,
    0xF9,
    0x04,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x2C,
    0x00,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x00,
    0x0A,
    0x00,
    0x00,
    0x02,
    0x16,
    0x8C,
    0x2D,
    0x99,
    0x87,
    0x2A,
    0x1C,
    0xDC,
    0x33,
    0xA0,
    0x02,
    0x75,
    0xEC,
    0x95,
    0xFA,
    0xA8,
    0xDE,
    0x60,
    0x8C,
    0x04,
    0x91,
    0x4C,
    0x01,
    0x00,
    0x3B
}

load_gif :: proc(data: []byte){

    EXTENSION_INTRODUCER :: 0x21

    data := example_gif

    signature := eat_bytes(&data, 3)
    assert(string(signature) == "GIF")

    version := eat_bytes(&data, 3)

    Descriptor :: bit_field u8 {
        color_table_size: uint | 3,
        color_table_sort_flag: bool | 1,
        color_resolution: uint | 3,
        global_color_table_flag: bool | 1,
    }
    LogicalDescriptor :: struct #packed {
        canvas_width, canvas_height: u16,
        descriptor: Descriptor,
        background_color_index: u8,
        pixel_aspect_ratio: u8,
    }

    logical_descriptor := eat_type(&data, LogicalDescriptor)

    descriptor := &logical_descriptor.descriptor
    log(descriptor^)

    color_table_length := 1 << (descriptor.color_resolution + 1)
    log(color_table_length)

    Color :: [3]u8
    color_table: []Color

    if descriptor.global_color_table_flag {
        color_table = eat_slice(&data, Color, int(color_table_length))
        // color_table = eat_bytes(&data, int(color_table_length) * 3)
    }

    for color in color_table {
        log_color({color.r, color.g, color.b, 255 })
    }

    ExtensionPacked :: bit_field u8 {
        transparent_color: bool | 1,
        user_input: bool | 1,
        disposal_method: int | 2,
        reserved: int | 3
    }

    GraphicsControlExtension :: struct #packed {
        introducer: u8 `fmt:"x"`,
        control_label: u8 `fmt:"x"`,
        byte_size: u8,
        packed: ExtensionPacked,
        delay_time: u16,
        transparent_color_index: u8,
        block_terminator: u8
    }

    assert(peek_bytes(data, 1)[0] == EXTENSION_INTRODUCER)

    graphics_control_extension := eat_type(&data, GraphicsControlExtension)
    log(graphics_control_extension)

    ImageDescriptorPacked :: bit_field u8 {
        local_color_table_size: int | 3,
        reserved: int | 2,
        sort: bool | 1,
        interlace: bool | 1,
        local_color_table: bool | 1
    }

    ImageDescriptor :: struct #packed {
        seperator: u8 `fmt:"x"`,
        image_left, image_top: u16,
        image_width, image_height: u16,
        packed: ImageDescriptorPacked,
    }

    image_descriptor := eat_type(&data, ImageDescriptor)
    log(image_descriptor)

    local_color_table: []u8

    if image_descriptor.packed.local_color_table {
        local_color_table = eat_bytes(&data, int(image_descriptor.packed.local_color_table_size) * 3)
    }

    {
        lzw_minimum_code_size := eat_type(&data, u8)
        log(lzw_minimum_code_size^)

        block := make([dynamic]u8, context.temp_allocator)
        for {
            sub_block_len :u8 = eat_type(&data, u8)^
            if sub_block_len == 0 do break
            sub_block := eat_bytes(&data, int(sub_block_len))
            append(&block, ..sub_block)
        }

        indexes := lzw_decompress(block[:], lzw_minimum_code_size^)

        width := int(logical_descriptor.canvas_width)
        height := int(logical_descriptor.canvas_height)

        has_transparency := graphics_control_extension.packed.transparent_color
        transparent_index := int(graphics_control_extension.transparent_color_index)

        image_bytes := width * height
        image_data := make([]rl.Color, image_bytes, context.temp_allocator)
        for index, i in indexes {
            alpha :u8 = 255
            if has_transparency && transparent_index == int(index) {
                alpha = 0
            }
            color := color_table[int(index)]
            image_data[i] = rl.Color { color.r, color.g, color.b, alpha }
        }

        log_image(image_data, width, height, 10)
    }

    next := eat_bytes(&data, 1)[0]

    assert(next != EXTENSION_INTRODUCER, "no support for plain text or application extensions")

    if next == 0x3B {
        log("DONE")
    }
}

lzw_decompress :: proc(data: []byte, min_code_size: u8, allocator := context.temp_allocator) -> []u16 {

    CodeExtractor :: struct {
        data: []u8,
        bit_index: int
    }
    extract_code :: proc(extractor: ^CodeExtractor, bits: u8) -> u16 {

        read_bits :: proc(ptr: [^]byte, offset, size: uintptr) -> (res: u64) {
    		for i in 0..<size {
    			j := i+offset
    			B := ptr[j/8]
    			k := j&7
    			if B & (u8(1)<<k) != 0 {
    				res |= u64(1)<<u64(i)
    			}
    		}
    		return
    	}
    	val := read_bits(&extractor.data[0], uintptr(extractor.bit_index), uintptr(bits))
    	extractor.bit_index += int(bits)
    	return u16(val)
    }

    extractor: CodeExtractor
    extractor.data = data

    Code :: u16
    Index :: u16
    MAX_CODES :: 4095
    Table :: sa.Small_Array(MAX_CODES, sa.Small_Array(MAX_CODES, Index))

    table_base_size := int(1 << min_code_size) + 2

    indexes := make([dynamic]Index, allocator = allocator)
    code_table := new(Table, context.temp_allocator)

    table_init :: proc(table: ^Table, base_size: int){
        sa.clear(table)
        sa.resize(table, base_size)
        for i in 0..<base_size - 2 {
            item := sa.get_ptr(table, i)
            sa.resize(item, 1)
            sa.set(item, 0, Index(i))
        }
    }
    table_log :: proc(table: ^Table){
        for &sequence, code in sa.slice(table) {
            log(fmt.tprintf("#{}", code), sa.slice(&sequence))
        }
    }
    table_get :: proc(table: ^Table, code: Code) -> (indexes: []Index, found: bool) {
        row := sa.get_ptr_safe(table, int(code)) or_return
        return sa.slice(row), true
    }

    table_append :: proc(table: ^Table, sequence: sa.Small_Array(MAX_CODES, Code), code_size: ^u8) -> bool {
        index := sa.len(table^)
        sequence := sequence
        res := sa.append(table, sequence)
        if res && index == (1 << code_size^) - 1 {
            code_size^ += 1
        }
        return res
    }

    code_size := min_code_size + 1

    initialized: bool

    previous_code: Code

    for {
        code := extract_code(&extractor, code_size)
        defer previous_code = code

        if code == 4 {
            table_init(code_table, table_base_size)
            continue
        }
        if code == 5 {
            break
        }

        // first proper code
        if !initialized {
            first_sequence, ok := table_get(code_table, code)
            assert(ok)
            append(&indexes, ..first_sequence)

            initialized = true
            continue
        }

        previous_sequence, found_previous := table_get(code_table, previous_code)

        if sequence, found := table_get(code_table, code); found {
            append(&indexes, ..sequence)
            k := sequence[0]
            assert(found_previous)
            new_sequence: sa.Small_Array(MAX_CODES, Index)
            sa.append(&new_sequence, ..previous_sequence)
            sa.append(&new_sequence, k)

            append_ok := table_append(code_table, new_sequence, &code_size)
            assert(append_ok)
        }
        else {
            assert(found_previous, fmt.tprint(code))
            k := previous_sequence[0]

            new_sequence: sa.Small_Array(MAX_CODES, Index)
            sa.append(&new_sequence, ..previous_sequence)
            sa.append(&new_sequence, k)

            append_ok := table_append(code_table, new_sequence, &code_size)
            assert(append_ok)

            append(&indexes, ..sa.slice(&new_sequence))
        }
    }

    return indexes[:]
}