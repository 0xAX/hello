%    __                        __      _
%   / /__________ __   _____  / /___  (_)___  ____ _
%  / __/ ___/ __ `/ | / / _ \/ / __ \/ / __ \/ __ `/
% / /_/ /  / /_/ /| |/ /  __/ / /_/ / / / / / /_/ /
% \__/_/   \__,_/ |___/\___/_/ .___/_/_/ /_/\__, /
%                           /_/            /____/
%
% Copyright (c) Travelping GmbH <info@travelping.com>

-module(jsonrpc_1_compliance_SUITE).

-behaviour(hello_service).
-export([method_info/0, param_info/1, handle_request/3]).
-compile(export_all).

-include("ct.hrl").
-include("../include/hello.hrl").

-define(REQ_ID, 1).

% ---------------------------------------------------------------------
% -- test cases
param_structures(_Config) ->
    % by-position
    Req1 = request("spec_suite_1", {"subtract", [2,1]}),
    1    = field(Req1, "result").

response_fields(_Config) ->
    % success case
    Req1 = request("spec_suite_1", {"subtract", [2,1]}),
    1         = field(Req1, "result"),
    ?REQ_ID   = field(Req1, "id"),
    null      = field(Req1, "error"),

    % error case
    Req2 = request("spec_suite_1", {"subtract", []}),
    null      = field(Req2, "result"),
    ?REQ_ID   = field(Req2, "id"),
    {_}  = field(Req2, "error").

notification(_Config) ->
    % leaving id off is treated as an invalid request
    % since we handle errors jsonrpc-2.0 style, this can be checked
    Res    = request("spec_suite_1", "{\"method\": \"subtract\", \"params\": [2, 1]}"),
    -32600 = field(Res, "error.code"),

    % null giving null for the id indicates a notification
    {no_json, <<"">>} = request("spec_suite_1", "{\"id\": null, \"method\": \"subtract\", \"params\": [2, 1]}").

% ---------------------------------------------------------------------
% -- service callbacks
method_info() ->
    [#rpc_method{name = subtract}].

param_info(subtract) ->
    [#rpc_param{name = subtrahend,
                type = number},
     #rpc_param{name = minuend,
                type = number}].

handle_request(_Req, subtract, [Subtrahend, Minuend]) ->
    {ok, Subtrahend - Minuend}.

% ---------------------------------------------------------------------
% -- common_test callbacks
all() -> [param_structures, response_fields, notification].

init_per_suite(Config) ->
	application:start(inets),
	application:start(hello),
	hello_service:register(spec_suite_1, ?MODULE),
	Config.

end_per_suite(_Config) ->
	hello_service:unregister(spec_suite_1),
	application:stop(hello),
	application:stop(inets).

% ---------------------------------------------------------------------
% -- utilities
request(Service, {Method, Params}) ->
    Req = {[{id, ?REQ_ID}, {method, list_to_binary(Method)}, {params, Params}]},
    request(Service, hello_json:encode(Req));
request(Service, Request) when is_list(Request) ->
    request(Service, list_to_binary(Request));
request(Service, Request) ->
    RespJSON = hello:handle_request(Service, Request),
    case hello_json:decode(RespJSON) of
        {ok, RespObj, _Rest}  -> RespObj;
        {error, syntax_error} -> {no_json, RespJSON}
    end.

field(Object, Field) ->
	Flist = re:split(Field, "\\.", [{return, list}]),
	lists:foldl(fun (Name, {CurProps}) ->
                    proplists:get_value(Name, CurProps)
			    end, Object, Flist).
