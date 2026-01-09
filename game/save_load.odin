package game

import "core:reflect"
import "core:mem"
import "core:os"
import "core:fmt"
import "base:runtime"
import "core:time"
import "core:strings"
import "base:intrinsics"
import "core:thread"
import sa "core:container/small_array"

discover_types :: proc(type: typeid , types: ^[dynamic]typeid){

    type_info := type_info_of(type)

    switch {
        case reflect.is_struct(type_info):
            for field in reflect.struct_fields_zipped(type){
                discover_types(field.type.id, types)
            }
        case reflect.is_array(type_info):
            array_info := reflect.type_info_base(type_info).variant.(reflect.Type_Info_Array)
            discover_types(array_info.elem.id, types)
            return
        case reflect.is_enumerated_array(type_info):
            array_info := reflect.type_info_base(type_info).variant.(reflect.Type_Info_Enumerated_Array)
            discover_types(array_info.elem.id, types)
            discover_types(array_info.index.id, types)
            return

        case reflect.is_bit_set(type_info):
            bit_set_info := reflect.type_info_base(type_info).variant.(reflect.Type_Info_Bit_Set)
            discover_types(bit_set_info.elem.id, types)
            return

        case reflect.is_enum(type_info):


        case:
            return
    }

    // quit if we've already added it
    for other in types {
        if other == type do return
    }

    append(types, type)
}



SaveField :: struct {
    name: StaticString(100),
    type: StaticString(100),
    offset: uintptr,
    size: int,
    elem_size: int,
}

Struct_Id :: distinct int
Enum_Id :: distinct int
Union_Id :: distinct int
Array_Id :: distinct int

Type_Id :: union {
    Struct_Id, Enum_Id, Union_Id, Array_Id
}

SaveStruct :: struct {
    name: StaticString(100),
    fields: sa.Small_Array(400, SaveField),
}

SaveEnumField :: struct {
    name: StaticString(100),
    value: i64,
}

SaveEnum :: struct {
    name: StaticString(100),
    fields: sa.Small_Array(200, SaveEnumField)
}

SaveHeader :: struct {
    structs: sa.Small_Array(200, SaveStruct),
    enums: sa.Small_Array(200, SaveEnum),
    data_size: int
}

save_to_file :: proc(v: ^$T, filename: string){
    bytes := serialize(v)
    defer delete(bytes)
    handle, err := os.open(filename, os.O_CREATE)
    assert(err == os.ERROR_NONE)
    defer os.close(handle)
    os.write(handle, bytes)
}

load_from_file :: proc(v: ^$T, filename: string){
    if !os.is_file(filename) do return

    handle, open_err := os.open(filename)
    assert(open_err == os.ERROR_NONE)
    defer os.close(handle)

    data, read_err := os.read_entire_file_or_err(handle)
    assert(read_err == os.ERROR_NONE)

    deserialize(v, data)

    delete(data)
}

serialize :: proc(state: ^$T, allocator := context.allocator) -> []u8 {

    types :[dynamic]typeid
    discover_types(type_of(state^), &types)

    header := new(SaveHeader)

    for type in types {

        type_info := type_info_of(type)

        if reflect.is_struct(type_info){

            save_struct: SaveStruct
            write_to_static(&save_struct.name, fmt.tprint(type))
            for field in reflect.struct_fields_zipped(type){
                save_field : SaveField
                write_to_static(&save_field.name, field.name)
                write_to_static(&save_field.type, fmt.tprint(field.type.id))
                save_field.offset = field.offset
                save_field.size = field.type.size
                #partial switch &v in field.type.variant {
                    case runtime.Type_Info_Array:
                    save_field.elem_size = v.elem_size
                    case runtime.Type_Info_Enumerated_Array:
                    save_field.elem_size = v.elem_size
                    case runtime.Type_Info_Union:
                    save_field.elem_size = transmute(int)(v.tag_offset)
                }

                sa.append(&save_struct.fields, save_field)
            }
            sa.append(&header.structs, save_struct)
        }
        if reflect.is_enum(type_info){

            save_enum: SaveEnum
            write_to_static(&save_enum.name, fmt.tprint(type))
            for field in reflect.enum_fields_zipped(type){
                save_field: SaveEnumField
                write_to_static(&save_field.name, field.name)
                save_field.value = i64(field.value)

                sa.append(&save_enum.fields, save_field)
            }

            sa.append(&header.enums, save_enum)
        }
    }

    header.data_size = size_of(T)

    bytes: [dynamic]byte

    append(&bytes, ..mem.ptr_to_bytes(header))
    append(&bytes, ..mem.ptr_to_bytes(state))

    return bytes[:]
}

deserialize :: proc(state: ^$T, data: []u8){

    save_header     := cast(^SaveHeader) &data[0]
    saved_state     := data[size_of(SaveHeader):size_of(SaveHeader) + save_header.data_size]
    saved_structs   := sa.slice(&save_header.structs)
    saved_enums     := sa.slice(&save_header.enums)

    when USE_TIMING {
        start := time.now()
        defer {
            fmt.println(time.duration_seconds(time.since(start)))
        }
    }

    ctx := Deserialization_Context {
        saved_enums = saved_enums,
        saved_structs = saved_structs
    }

    context.allocator = context.temp_allocator

    write_across(&ctx, uintptr(&saved_state[0]), uintptr(state), type_info_of(T), len(saved_state))

    SHOW_IDENTICAL :: false

    when SHOW_IDENTICAL {
    fmt.println("IDENTICAL ------")
    for v, i in ctx.identical {
        fmt.println(v, " : ", i)
    }
    fmt.println("---------------")
    }
}

Deserialization_Context :: struct {
    // caching and timer
    timer_map: map[string]f64,
    id_to_struct: map[^runtime.Type_Info]^SaveStruct,
    id_to_enum: map[^runtime.Type_Info]^SaveEnum,
    struct_fields: map[struct{^SaveStruct, string}]^SaveField,
    identical: map[typeid]bool,
    enum_field_identical: map[^SaveEnumField]bool,

    saved_structs: []SaveStruct,
    saved_enums: []SaveEnum,
}

USE_CACHING :: true
USE_TIMING :: false


PolyStruct :: struct {
    name: string,
    parameters: []PolyParameter
}

PolyParameter :: struct {
    name: string,
    value: string,
    is_int: bool
}

is_int :: proc(s: string) -> bool{
    for r in s {
        if r < '0' || r > '9' do return false
    }
    return true
}

parse_parapoly :: proc(s: string) -> (ps: PolyStruct, b: bool) {
    index := strings.index(s, "(")

    s_len := len(s)
    if index == -1 do return
    ps.name = s[:index]
    params: [dynamic]PolyParameter
    params.allocator = context.temp_allocator

    index += 1
    s := s[index:]
    s = s[:len(s) - 2]

    string_params, p_err := strings.split(s, ",")
    assert(p_err == nil)

    for p in string_params {
        param := strings.trim_space(p)
        values, v_err := strings.split(param, "=")
        assert(v_err == nil)
        append(&params, PolyParameter { values[0], values[1], is_int(values[1]) })
    }

    ps.parameters = params[:]
    return ps, true
}

parapoly_equal :: proc(a, b: PolyStruct) -> bool {
    if a.name != b.name do return false
    if len(a.parameters) != len(b.parameters) do return false
    for i in 0..<len(a.parameters){
        a_param := a.parameters[i]
        b_param := b.parameters[i]
        if a_param.name != b_param.name do return false
        if a_param.value == b_param.value do continue
        if !(a_param.is_int && b_param.is_int) do return false
    }
    return true
}

write_across :: proc(using ctx: ^Deserialization_Context, saved: uintptr, actual: uintptr, type: ^runtime.Type_Info, saved_size: int) -> bool {


    find_matching_struct :: proc(using ctx: ^Deserialization_Context, type: ^runtime.Type_Info) -> (result: ^SaveStruct, ok: bool) {
        when USE_TIMING {
            start := time.now()
            defer {
                timer_map["match struct"] += time.duration_seconds(time.since(start))
            }
        }

        if identical[type.id] {
            return nil, false
        }

        when USE_CACHING {
            cached, exists := id_to_struct[type]
            if exists {
                return cached, true
            }
        }

        type_name := fmt.tprint(type)


        struct_names_equal :: proc(a, b: string) -> bool {
            if a == b do return true

            //return false


            index_a := strings.index(a, "(")
            index_b := strings.index(b, "(")

            if index_a == -1 || index_b == -1 do return false

            start_a := a[:index_a]
            start_b := b[:index_b]

            if start_a == start_b do return true
            return false
        }

        for &saved_struct in saved_structs {
            if static_to_string(&saved_struct.name) == type_name {
                when USE_CACHING {
                    id_to_struct[type] = &saved_struct
                }
                return &saved_struct, true
            }
        }

        { // check parapoly

            b_para := parse_parapoly(type_name) or_return

            for &saved_struct in saved_structs {
                a_para := parse_parapoly(static_to_string(&saved_struct.name)) or_continue
                if parapoly_equal(a_para, b_para) do return &saved_struct, true
            }
        }

        return nil, false
    }

    find_matching_enum :: proc(using ctx: ^Deserialization_Context, type: ^runtime.Type_Info) -> (result: ^SaveEnum, ok: bool){

        when USE_CACHING {
            e, exists := id_to_enum[type]
            if exists do return e, true
        }

        type_name := fmt.tprint(type)

        for &saved_enum in saved_enums {
            if static_to_string(&saved_enum.name) == type_name {
                when USE_CACHING {
                    id_to_enum[type] = &saved_enum
                }
                return &saved_enum, true
            }
        }
        return nil, false
    }

    find_matching_field :: proc(using ctx: ^Deserialization_Context, save_struct: ^SaveStruct, field_name: string) -> (result: ^SaveField, ok: bool) {

        when USE_TIMING {
            start := time.now()
            defer {
                timer_map["match field"] += time.duration_seconds(time.since(start))
            }
        }

        key: struct{^SaveStruct, string } = { save_struct, field_name }
        when USE_CACHING{
            cached, exists := struct_fields[key]
            if exists {
                return cached, true
            }
        }

        for &saved_field in sa.slice(&save_struct.fields) {
            if static_to_string(&saved_field.name) == field_name {
                when USE_CACHING {
                    struct_fields[key] = &saved_field
                }
                return &saved_field, true
            }
        }
        return nil, false
    }

    enums_equal :: proc(saved_size: int, saved: ^SaveEnum, actual: ^runtime.Type_Info) -> bool {
        if saved_size != actual.size do return false
        saved_fields := sa.slice(&saved.fields)
        actual_fields := reflect.enum_fields_zipped(actual.id)
        if len(saved_fields) != len(actual_fields) do return false

        for &field, i in actual_fields {
            if field.name != static_to_string(&saved_fields[i].name) do return false
        }
        return true
    }

    switch {
    case reflect.is_struct(type):
        saved_struct := find_matching_struct(ctx, type) or_break

        identical_count :int = 0
        struct_fields := reflect.struct_fields_zipped(type.id)
        for field in struct_fields {
            if field.tag == reflect.Struct_Tag("no_save") do continue
            saved_field, ok := find_matching_field(ctx, saved_struct, field.name)

            if !ok {
                identical_count = 0
                continue
            }

            if saved_field.offset != field.offset {
                identical_count = 0
            }

            saved_value := saved + saved_field.offset
            actual_value := actual + field.offset

            #partial switch &v in field.type.variant {
                case runtime.Type_Info_Array:

                if reflect.is_struct(v.elem) {
                    array_identical: int
                    count := min(saved_field.size / saved_field.elem_size, v.count)
                    for i in 0..<count {
                        array_saved := saved_value + uintptr(i * saved_field.elem_size)
                        array_actual := actual_value + uintptr(i * v.elem_size)

                        if write_across(ctx, array_saved, array_actual, v.elem, saved_field.elem_size) {
                            array_identical += 1
                        }
                    }
                    if array_identical == count {
                        identical_count += 1
                    }
                    continue
                }
                case runtime.Type_Info_Union:
                    saved_offset :uintptr = transmute(uintptr)saved_field.elem_size

                    if saved_offset == v.tag_offset do break // union size hasnt changed

                    saved_tag := cast(^u64)(saved_value + saved_offset)
                    actual_tag := cast(^u64)(actual_value + v.tag_offset)

                    actual_tag ^= saved_tag^ // copy the union tag across
                    if saved_tag^ == 0 do break

                    variant :^runtime.Type_Info = v.variants[saved_tag^ - 1] // union tags start at 1


                    field_size := int(saved_offset - saved_value)


                    write_across(ctx, saved_value, actual_value, variant, int(saved_offset))
                    continue

                case runtime.Type_Info_Enumerated_Array:
                    // if identical[v.index.id] && identical[v.elem.id] do break

                    saved_enum, found_matching_enum := find_matching_enum(ctx, v.index)
                    assert(found_matching_enum, fmt.tprint(v.index))
                    array_identical: int

                    count := min(saved_field.size / saved_field.elem_size, v.count)

                    for &saved_index_field in sa.slice(&saved_enum.fields) {
                        saved_name := static_to_string(&saved_index_field.name)
                        for actual_field in reflect.enum_fields_zipped(v.index.id) {
                            if saved_name != actual_field.name do continue
                            array_saved := saved_value + uintptr(int(saved_index_field.value) * saved_field.elem_size)
                            array_actual := actual_value + uintptr(int(actual_field.value) * v.elem_size)

                            if write_across(ctx, array_saved, array_actual, v.elem, saved_field.elem_size){
                                array_identical += 1
                            }
                        }
                        if array_identical == count {
                            identical_count += 1
                        }
                    }
                    continue

                case runtime.Type_Info_Dynamic_Array, runtime.Type_Info_Map:
                    identical_count += 1
                    intrinsics.mem_zero(rawptr(actual), field.type.size)
                    continue
            }

            if write_across(ctx, saved_value, actual_value, field.type, saved_field.size){
                identical_count += 1
            }
        }

        if identical_count == len(struct_fields){
            identical[type.id] = true
            return true
        }
        return false

    case reflect.is_enum(type):
        saved_enum := find_matching_enum(ctx, type) or_break

        if _, found := identical[type.id]; !found {
            identical[type.id] = enums_equal(saved_size, saved_enum, type)
        }


        if type.size != size_of(i64) do break

        saved_value :^i64 = cast(^i64)saved
        actual_value: ^i64 = cast(^i64)actual


        if identical[type.id] {
            actual_value^ = saved_value^
            return true
        }

        save_field: ^SaveEnumField
        saved_name: string
        for &field in sa.slice(&saved_enum.fields){
            if field.value != saved_value^ do continue
            save_field = &field
            saved_name = static_to_string(&field.name)
            break
        }

        for &field in reflect.enum_fields_zipped(type.id){
            if field.name != saved_name do continue
            actual_value^ = i64(field.value)
        }

        return false

    case reflect.is_enumerated_array(type):
        v := type.variant.(reflect.Type_Info_Enumerated_Array)

        if identical[v.index.id] && identical[v.elem.id] do break

        saved_enum, found_matching_enum := find_matching_enum(ctx, v.index)
        assert(found_matching_enum, fmt.tprint(v.index))
        array_identical: int

        saved_elem_size := saved_size / sa.len(saved_enum.fields)

        count := min(sa.len(saved_enum.fields), v.count)


        for &saved_index_field in sa.slice(&saved_enum.fields) {
            saved_name := static_to_string(&saved_index_field.name)
            for actual_field in reflect.enum_fields_zipped(v.index.id) {
                if saved_name != actual_field.name do continue
                array_saved := saved + uintptr(int(saved_index_field.value) * saved_elem_size)
                array_actual := actual + uintptr(int(actual_field.value) * v.elem_size)

                if write_across(ctx, array_saved, array_actual, v.elem, saved_elem_size){
                    array_identical += 1
                }
            }
        }

        if array_identical == count {
            identical[type.id] = true
            return true
        }
        return false


    case reflect.is_union(type):
        union_info := type.variant.(reflect.Type_Info_Union)


    case reflect.is_bit_set(type):

        bit_set_info := reflect.type_info_base(type).variant.(reflect.Type_Info_Bit_Set)
        enum_type := bit_set_info.elem
        saved_enum := find_matching_enum(ctx, enum_type) or_break

        if _, found := identical[enum_type.id]; !found {
            identical[enum_type.id] = enums_equal(size_of(i64), saved_enum, enum_type)
        }

        saved_value: []byte = mem.byte_slice(rawptr(saved), saved_size)
        new_value : []byte = mem.byte_slice(rawptr(actual), type.size)

        if identical[enum_type.id] {
            copy(new_value, saved_value)
            return true
        }

        for &saved_field in sa.slice(&saved_enum.fields) {
            _byte :u64 = u64(saved_field.value / 8)
            bit :u64 = u64(saved_field.value % 8)

            saved_byte := saved_value[_byte]
            is_set :bool  = ((u8(1) << bit) & saved_byte) > 0

            assert(reflect.is_enum(bit_set_info.elem))

            saved_name := static_to_string(&saved_field.name)

            for &field in reflect.enum_fields_zipped(bit_set_info.elem.id){
                if field.name == saved_name {
                    byte_actual: u64 = u64(field.value / 8)
                    bit_actual : u64 = u64(field.value % 8)

                    if is_set {
                        new_value[byte_actual] |= 1 << bit_actual
                    }
                    else {
                        new_value[byte_actual] &= ~(1 << bit_actual)
                    }
                }
            }
        }
        return false
    }

    size := min(type.size, saved_size)
    mem.copy(rawptr(actual), rawptr(saved), size)
    return true
}