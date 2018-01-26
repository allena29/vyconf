exception Missing_field of string

type t = {
    app_name: string;
    data_dir: string;
    program_dir: string;
    config_dir: string;
    primary_config: string;
    fallback_config: string;
    socket: string;
    pid_file: string;
    log_file: string option;
    log_template: string;
    log_level: string;
} [@@deriving show]

(* XXX: there should be a better way than to fully initialize it
        with garbage just to update it later *)
let empty_config = {
    app_name = "";
    data_dir = "";
    program_dir = "";
    config_dir = "";
    primary_config = "";
    fallback_config = "";
    socket = "";
    pid_file = "";
    log_file = None;
    log_template = "";
    log_level = "";
}


(* XXX: We assume that nesting in TOML config files never goes beyond two levels  *)

let get_field conf tbl_name field_name =
    try
        Some (Toml.get_string (Toml.key field_name) (Toml.get_table (Toml.key tbl_name) conf))
    with Not_found -> None

let mandatory_field conf table field =
    let value = get_field conf table field in
    match value with
    | Some value -> value
    | None -> raise @@ Missing_field (Printf.sprintf "Invalid config: Missing mandatory field \"%s\" in section [%s]" field table)

let optional_field default conf table field =
    let value = get_field conf table field in
    BatOption.default default value

let load filename =
    try
        let open Defaults in
        let conf_toml = Toml.Parser.from_filename filename  in
        let conf = empty_config in
            (* Mandatory fields *)
            let conf = {conf with app_name = mandatory_field conf_toml "appliance" "name"} in
            let conf = {conf with data_dir = mandatory_field conf_toml "appliance" "data_dir"} in
            let conf = {conf with config_dir = mandatory_field conf_toml "appliance" "config_dir"} in
            let conf = {conf with program_dir = mandatory_field conf_toml "appliance" "program_dir"} in
            let conf = {conf with primary_config = mandatory_field conf_toml "appliance" "primary_config"} in
            let conf = {conf with fallback_config = mandatory_field conf_toml "appliance" "fallback_config"} in
            (* Optional fields *)
            let conf = {conf with pid_file = optional_field defaults.pid_file conf_toml "vyconf" "pid_file"} in
            let conf = {conf with socket = optional_field defaults.socket conf_toml "vyconf" "socket"} in
            let conf = {conf with log_template = optional_field defaults.log_template conf_toml "vyconf" "log_template"} in
            let conf = {conf with log_level = optional_field defaults.log_level conf_toml "vyconf" "log_level"} in
            (* log_file is already string option, so we don't need to unwrap *)
            let conf = {conf with log_file = get_field conf_toml "vyconf" "log_file"} in
            Result.Ok conf
    with
    | Sys_error msg -> Error msg
    | Toml.Parser.Error (msg, _) -> Error msg
    | Missing_field msg -> Error msg

let dump  = show
