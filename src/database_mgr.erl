-module(database_mgr).

-behaviour(gen_server).

% Public API.
-export([
    add_node_to_space/2,
    create_new_space/1,
    list_nodes_in_space/1,
    remove_node_from_space/2,
    start_link/0
]).

% gen_server callbaks.
-export([
    code_change/3,
    init/1, 
    handle_call/3, 
    handle_cast/2, 
    handle_info/2, 
    terminate/2
]).

% Creates a new tuple space local to this node.
create_new_space(SpaceName) ->
    gen_server:call(?MODULE, {create_space, SpaceName}).

% Adds given node to given tuple space.
add_node_to_space(Node, Space) -> 
    try 
        NodeInSpace = is_node_in_space(node(), Space),
        if
            NodeInSpace ->
                gen_server:call({?MODULE, Node}, {enter_space, Space});
            true -> {error, {node_not_in_space, node(), Space}}
        end
    catch
        exit:{{nodedown,N},_} -> {error, {no_node, N}};
        _:Error -> {error, Error}
    end.

% Remove given node from given tuple space.
remove_node_from_space(Node, Space) when is_atom(Node), is_atom(Space) -> 
    try
        NodeInSpace = is_node_in_space(node(), Space),
        if
            NodeInSpace ->
                gen_server:call({?MODULE, Node}, {exit_space, Space});
            true -> {error, {node_not_in_space, node(), Space}}
        end
    catch
        exit:{{nodedown,N},_} -> {error, {no_node, N}};
        _:Error -> {error, Error}
    end.

% Returns a list of all nodes in this tuple space.
list_nodes_in_space(Space) -> 
    IsNodeInSpace = is_node_in_space(node(), Space),
    if
        IsNodeInSpace -> gen_server:call(?MODULE, {nodes_in_space, Space});
        true -> {error, {node_not_in_space, node(), Space}}
    end.

% Start an instance of db.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%%%%%%%%%%%%%%%%%%%%
% gen_server callbacks
%%%%%%%%%%%%%%%%%%%%%%

% init/1 callback from gen_server.
init(_Args) ->
    process_flag(trap_exit, true),
    % Start mnesia with the default schema;
    % the schema is manipulated with messages.
    case init_cluster() of
        ok -> {ok, []};
        {error, Reason} -> {stop, Reason}
    end.

% handle_call/3 callback from gen_server.
handle_call({create_space, Name}, _From, _State) ->
    % Create a new space with given name and start a new ts_mgr
    Res = case create_space(Name) of
        ok -> ts_supervisor:add_space_manager(Name);
        Error -> Error
    end,
    {reply, Res, _State};
handle_call({enter_space, Space}, _From, _State) ->
    % Add this node to given space and start a new ts_mgr
    Res = case addme_to_space(Space) of
        ok -> ts_supervisor:add_space_manager(Space);
        Error -> Error
    end,
    {reply, Res, _State};
handle_call({exit_space, Space}, _From, _State) ->
    % Remove this node form given space and stop his ts_mgr
    Res = case removeme_from_space(Space) of
        ok -> ts_supervisor:del_space_manager(Space);
        Error -> Error
    end,
    {reply, Res, _State};
handle_call({nodes_in_space, Space}, _From, _State) ->
    % List all nodes in given space
    Nodes = nodes_in_space(Space),
    {reply, {ok, Nodes}, _State};
handle_call(stop, _From, _State) ->
    {stop, normal, stopped, _State};
handle_call(_Request, _From, _State) ->
    {reply, {error, bad_request}, _State}.

% handle_cast/2 callback from gen_server.
handle_cast(_Msg, _State) ->
    {noreply, _State}.

% handle_info/2 callback from gen_server.
handle_info(_Info, _State) ->
    {noreply, _State}.

% terminate/2 callback from gen_server.
terminate(_Reason, _State) ->
    ensure_stopped(),
    ok.

% code_change/3 callback from gen_server.
code_change(_OldVsn, _State, _Extra) ->
    {ok, _State}.

% Funzioni interne

% Ensures mnesia db is running.
ensure_started() -> 
    mnesia:start(),
    wait_for(start).

% Ensures mnesia db is not running.
ensure_stopped() -> 
    mnesia:stop(),
    wait_for(stop).

% Wait for mnesia db to start/stop.
wait_for(start) -> 
    case mnesia:system_info(is_running) of
        yes -> ok;
        no -> {error, mnesia_unexpectedly_not_running};
        stopping -> {error, mnesia_unexpectedly_stopping};
        starting -> 
            timer:sleep(1000),
            wait_for(start)
    end;
wait_for(stop) -> 
    case mnesia:system_info(is_running) of
        no -> ok;
        yes -> {error, mnesia_unexpectedly_running};
        starting -> {error, mnesia_unexpectedly_starting};
        stopping -> 
            timer:sleep(1000),
            wait_for(stop)
    end.

% Initialize the main cluster with all the nodes 
% connected to the colling one.
init_cluster() ->
    try
        ok = ensure_started(),
        ok = sync_cluster(),
        ok = create_disc_schema(),
        ok = ensure_nodes_table(),
        ok = wait_for_tables(),
        ok = restart_space_managers(),
        ok
    catch
        error:{badmatch, {timeout, Tab}} -> {error, {cannot_find_tables, Tab}};
        error:{badmatch, Error} -> Error;
        _:Error -> {error, Error}
    end.

% Set all nodes as extra_db_nodes end if the schema merge fail
% clear the schema and sync with the cluster.
sync_cluster() ->
    case mnesia:change_config(extra_db_nodes, nodes()) of
        {ok, _} -> ok;
        {error, {merge_schema_failed, _}} ->
            ok = ensure_stopped(),
            ok = mnesia:delete_schema([node()]),
            ok = ensure_started(),
            {ok, _} = mnesia:change_config(extra_db_nodes, nodes()),
            ok
    end.

% Creates a mnesia schema as disc_copies.
create_disc_schema() -> 
    case mnesia:change_table_copy_type(schema, node(), disc_copies) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, schema, _, _}} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

% Ensure the nodes table is present in the current cluster
% every node must have this table so if it's not present we
% create it.
ensure_nodes_table() ->
    Exist = lists:member(nodes, mnesia:system_info(tables)),
    if 
        Exist -> 
            % Check if the nodes table is a disc_copy or remote;
            % if it's remote or ram_copies (if it is it's a bug) copy
            % it locally
            case mnesia:table_info(nodes, storage_type) of
                disc_copies -> ok;
                _ -> 
                    case mnesia:add_table_copy(nodes, node(), disc_copies) of
                        {atomic, ok} -> ok;
                        {aborted, {already_exists, nodes, _}} -> ok;
                        {aborted, Reason} -> {error, Reason}
                    end
            end;
        true -> 
            % Create a new nodes table
            case mnesia:create_table(nodes, 
                [{type, bag}, {disc_copies, [node()]}]) of
                {atomic, ok} -> ok;
                {aborted, {already_exists, nodes}} -> ok;
                {aborted, Reason} -> {error, Reason}
            end
    end.

% Wait for all the tables locally stored in the node (nodes+spaces) to be
% fully loaded and force the load if it fails.
wait_for_tables() ->
    Tables = lists:filter(fun(Table) ->
        mnesia:table_info(Table, storage_type) =:= disc_copies
    end, mnesia:system_info(tables)),
    case mnesia:wait_for_tables(Tables, 2000) of
        ok -> ok;
        {timeout, MissingTables} -> 
            lists:foreach(fun(MissingTab) ->
                mnesia:force_load_table(MissingTab)
            end, MissingTables),
            ok
    end.

% Restart ts_managager for all spaces where the local node
% is in.
% This function is usefull when the node is restarted and all
% the old spaces are still present, their ts_mgr will be
% restarted
restart_space_managers() ->
    {atomic, SpacesRecords} = mnesia:transaction(fun() ->
        mnesia:match_object({nodes, '_', node()})
    end),
    lists:foreach(fun({_,Space,_Node}) ->
        ok = ts_supervisor:add_space_manager(Space)
    end, SpacesRecords),
    ok.

% Create a new tuple space with given name.
% This function returns error if a space with the same
% name already exist.
create_space(Name) ->
    try
        {atomic, ok} = mnesia:create_table(Name, [{type, bag}, {disc_copies, [node()]}]),
        {atomic, ok} = addme_to_nodes_unsafe(Name),
        ok
    catch
        error:{badmatch, {aborted, Error}} -> {error, Error}
    end.

% Add this node to the given tuple space.
% This function returns error if the node is already in the tuple space
addme_to_space(Space) ->
    try
        {atomic, ok} = mnesia:add_table_copy(Space, node(), disc_copies),
        {atomic, ok} = addme_to_nodes_unsafe(Space),
        ok
    catch
        error:{badmatch,{aborted, Error}} -> {error, Error}
    end.

% Remove this node from the given tuple space.
% This function returns error if the node is not in the tuple space
removeme_from_space(Space) ->
    try
        {atomic, ok} = mnesia:del_table_copy(Space, node()),
        {atomic, ok} = delme_to_nodes_unsafe(Space),
        ok
    catch
        error:{badmatch, {aborted, Error}} -> {error, Error}
    end.

% List all nodes connected to the given tuple space.
nodes_in_space(Space) ->
    case mnesia:transaction(fun() ->
        mnesia:read(nodes, Space)
    end) of
        {atomic, Nodes} -> lists:map(fun({_,_,E}) -> E end, Nodes);
        {aborted, _} -> []
    end.

% Returns true if the given node is in the given space; false otherwise.
is_node_in_space(Node, Space) ->
    lists:member(Node, nodes_in_space(Space)).

% Add the current node to the given space inside the nodes shared table.
% This operation is usafe because it resurns unsafe_result like the mnesia ones.
addme_to_nodes_unsafe(Space)->
    mnesia:transaction(fun() -> mnesia:write({nodes, Space, node()}) end).

% Remove the current node from the given space inside the nodes shared table.
% This operation is usafe because it resurns unsafe_result like the mnesia ones.
delme_to_nodes_unsafe(Space) ->
    mnesia:transaction(fun() -> mnesia:delete_object({nodes, Space, node()}) end).
