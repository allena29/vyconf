module CT = Config_tree
module RT = Reference_tree
module D = Directories

exception Session_error of string

type cfg_op =
    | CfgSet of string list * string option * CT.value_behaviour
    | CfgDelete of string list * string	option

type world = {
    running_config: CT.t;
    reference_tree: RT.t;
    vyconf_config: Vyconf_config.t;
    dirs: Directories.t
}

type session_data = {
    proposed_config : Config_tree.t;
    modified: bool;
    conf_mode: bool;
    changeset: cfg_op list;
    client_app: string;
    user: string;
}

let make world client_app user = {
    proposed_config = world.running_config;
    modified = false;
    conf_mode = false;
    changeset = [];
    client_app = client_app;
    user = user
}

let string_of_op op =
    match op with
    | CfgSet (path, value, _) ->
        let path_str = Util.string_of_list path in
        (match value with
         | None -> Printf.sprintf "set %s" path_str
         | Some v -> Printf.sprintf "set %s \"%s\"" path_str v)
    | CfgDelete (path, value) ->
        let path_str = Util.string_of_list path in
        (match value with
         | None -> Printf.sprintf "delete %s" path_str
         | Some v -> Printf.sprintf "delete %s \"%s\"" path_str v)


let set_modified s =
    if s.modified = true then s
    else {s with modified = true}

let apply_cfg_op op config =
    match op with
    | CfgSet (path, value, value_behaviour) ->
        CT.set config path value value_behaviour
    | CfgDelete (path, value) -> 
        CT.delete config path value

let rec apply_changes changeset config =
    match changeset with
    | [] -> config
    | c :: cs -> apply_changes cs (apply_cfg_op c config)

let set w s path =
    let path, value = RT.validate_path D.(w.dirs.validators) w.reference_tree path in
    let value_behaviour = if RT.is_multi w.reference_tree path then CT.AddValue else CT.ReplaceValue in
    let op = CfgSet (path, value, value_behaviour) in
    let config = apply_cfg_op op s.proposed_config in
    {s with proposed_config=config; changeset=(op :: s.changeset)}

let delete w s path =
    let path, value = RT.validate_path D.(w.dirs.validators) w.reference_tree path in
    let op = CfgDelete (path, value) in
    let config = apply_cfg_op op s.proposed_config in
    {s with proposed_config=config; changeset=(op :: s.changeset)}

let get_value w s path =
    if not (Vytree.exists s.proposed_config path) then
        raise (Session_error ("Path does not exist"))
    else if not (RT.is_leaf w.reference_tree path) then
        raise (Session_error "Cannot get a value of a non-leaf node")
    else if (RT.is_multi w.reference_tree path) then
        raise (Session_error "This node can have more than one value")
    else if (RT.is_valueless w.reference_tree path) then
        raise (Session_error "This node can have more than one value")
    else CT.get_value s.proposed_config path

let get_values w s path =
    if not (Vytree.exists s.proposed_config path) then
        raise (Session_error ("Path does not exist"))
    else if not (RT.is_leaf w.reference_tree path) then
        raise (Session_error "Cannot get a value of a non-leaf node")
    else if not (RT.is_multi w.reference_tree path) then
        raise (Session_error "This node can have only one value")
    else  CT.get_values s.proposed_config path

let list_children w s path =
    if not (Vytree.exists s.proposed_config path) then
        raise (Session_error ("Path does not exist"))
    else if (RT.is_leaf w.reference_tree path) then
        raise (Session_error "Cannot list children of a leaf node")
    else Vytree.children_of_path s.proposed_config path

let exists w s path =
    Vytree.exists s.proposed_config path

let show_config w s path fmt =
    let open Vyconf_types in
    if not (Vytree.exists s.proposed_config path) then
        raise (Session_error ("Path does not exist")) 
    else
        let node = Vytree.get s.proposed_config path in
        match fmt with
        | Curly -> CT.render node
        | Json -> CT.to_yojson node |> Yojson.Safe.pretty_to_string
