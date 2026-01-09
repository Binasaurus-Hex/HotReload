package game

import "core:reflect"
import "core:mem"
import rt "base:runtime"
import sa "core:container/small_array"
import "core:fmt"
import rl "vendor:raylib"

serialize_2 :: proc(t: ^$T, allocator := context.temp_allocator) -> []byte {
    types := discover_types_2(T)

    header := new(SaveHeader2, context.temp_allocator)

    save_type :: proc(header: ^SaveHeader2, type: typeid) -> TypeInfo_Handle {

        for info, i in sa.slice(&header.types){
            if info.id != type do continue
            return TypeInfo_Handle(i + 1)
        }

        info := type_info_of(type)
        save_info := TypeInfo {
            size = info.size,
            id = type
        }
        #partial switch v in info.variant {
        case rt.Type_Info_Named:
            save_info.variant = TypeInfo_Named {
                name = to_index_string(&header.strings, v.name),
                type = save_type(header, v.base.id)
            }
        case rt.Type_Info_Struct:
            save_struct := TypeInfo_Struct {}
            for field in reflect.struct_fields_zipped(type){
                sa.append(&save_struct.fields, Struct_Field {
                    name = to_index_string(&header.strings, field.name),
                    offset = field.offset,
                    type = save_type(header, field.type.id)
                })
            }
            save_info.variant = save_struct
        }
        sa.append(&header.types, save_info)
        return TypeInfo_Handle(sa.len(header.types))
    }

    for type in types {
        save_type(header, type)
    }

    for info, i in sa.slice(&header.types){
        log(i, ":", info.id)
    }
    log("// END //")
    log("")
    log("")

    for info, i in sa.slice(&header.types){
        if info.id != T do continue
        header.stored_type = TypeInfo_Handle(i + 1)
    }

    bytes := make([dynamic]byte, allocator)
    append(&bytes, ..mem.ptr_to_bytes(header))
    append(&bytes, ..mem.ptr_to_bytes(t))
    return bytes[:]
}

get_typeinfo_base :: proc(header: ^SaveHeader2, handle: TypeInfo_Handle) -> (base: ^TypeInfo, ok: bool){
    handle := handle
    for {
        base = get_typeinfo_ptr(header, handle) or_return
        named := base.variant.(TypeInfo_Named) or_break
        handle = named.type
    }
    return base, true
}

get_typeinfo_ptr :: proc(header: ^SaveHeader2, handle: TypeInfo_Handle) -> (ptr: ^TypeInfo, ok: bool) {
    index := int(handle) - 1
    return sa.get_ptr_safe(&header.types, index)
}

deserialize_2 :: proc(t: ^$T, data: []byte) {
    header := cast(^SaveHeader2)&data[0]
    body := data[size_of(SaveHeader2):]

    start, ok := get_typeinfo_ptr(header, header.stored_type)
    assert(ok)

    identical := deserialize_raw(header, uintptr(&body[0]), uintptr(t), header.stored_type, type_info_of(T))
    log("is identical ? ", identical)
}

find_matching_field :: proc(header: ^SaveHeader2, struct_info: ^TypeInfo_Struct, name: string) -> (^Struct_Field, bool) {
    for &field in sa.slice(&struct_info.fields){
        if resolve_to_string(&header.strings, field.name) != name do continue
        return &field, true
    }
    return nil, false
}

deserialize_raw :: proc(header: ^SaveHeader2, src, dst: uintptr, src_type: TypeInfo_Handle, dst_type: ^rt.Type_Info) -> (identical: bool){
    saved_type, found_saved := get_typeinfo_base(header, src_type)
    assert(found_saved)

    identical = true

    switch {
    case reflect.is_struct(dst_type):
        saved_struct := (&saved_type.variant.(TypeInfo_Struct)) or_break
        identical_fields: int = 0

        fields := reflect.struct_fields_zipped(dst_type.id)
        for field in fields {
            saved_field := find_matching_field(header, saved_struct, field.name) or_continue
            if saved_field.offset != field.offset do identical = false
            field_src := src + saved_field.offset
            field_dst := dst + field.offset
            if deserialize_raw(header, field_src, field_dst, saved_field.type, field.type){
                identical_fields += 1
            }
        }
        if identical_fields != len(fields) do identical = false
        return
    }

    if saved_type.size != dst_type.size do identical = false

    // fallback option
    log("|| falling through for", dst_type.id, " ||")
    size := min(saved_type.size, dst_type.size)
    mem.copy(rawptr(dst), rawptr(src), size)
    return
}


discover_types_raw :: proc(type: typeid , types: ^[dynamic]typeid){

    type_info := type_info_of(type)

    switch {
    case reflect.is_struct(type_info):
        for field in reflect.struct_fields_zipped(type){
            discover_types_raw(field.type.id, types)
        }
    case reflect.is_array(type_info):
        array_info := reflect.type_info_base(type_info).variant.(reflect.Type_Info_Array)
        discover_types_raw(array_info.elem.id, types)
        return

    case reflect.is_bit_set(type_info):
        bit_set_info := reflect.type_info_base(type_info).variant.(reflect.Type_Info_Bit_Set)
        discover_types_raw(bit_set_info.elem.id, types)
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

discover_types_2 :: proc(type: typeid, allocator := context.temp_allocator) -> []typeid {
    types := make([dynamic]typeid, allocator)
    discover_types_raw(type, &types)
    return types[:]
}

TypeInfo_Handle :: distinct int

Struct_Field :: struct {
    name: IndexString,
    offset: uintptr,
    type: TypeInfo_Handle
}

TypeInfo_Struct :: struct {
    fields: sa.Small_Array(100, Struct_Field)
}

TypeInfo_Named :: struct {
    name: IndexString,
    type: TypeInfo_Handle
}

TypeInfo :: struct {
    size: int,
    id: typeid,
    variant: union {
        TypeInfo_Named,
        TypeInfo_Struct
    }
}

SaveHeader2 :: struct {
    types: sa.Small_Array(400, TypeInfo),
    strings: sa.Small_Array(2000, byte),
    stored_type: TypeInfo_Handle,
}


// string stuff

to_index_string :: proc(buffer: ^sa.Small_Array($S, byte), s: string) -> IndexString {
    index := sa.len(buffer^)
    length := len(s)
    buffer.len += length
    copy_slice(buffer.data[index:index + length], transmute([]byte)s)
    return IndexString {
        index, length
    }
}

resolve_to_string :: proc(buffer: ^sa.Small_Array($T, byte), is: IndexString) -> string {
    s := sa.slice(buffer)
    return string(s[is.index: is.index + is.length])
}

IndexString :: struct {
    index, length: int
}
