% Copyright (c) 2010-2011 by Travelping GmbH <info@travelping.com>

% Permission is hereby granted, free of charge, to any person obtaining a
% copy of this software and associated documentation files (the "Software"),
% to deal in the Software without restriction, including without limitation
% the rights to use, copy, modify, merge, publish, distribute, sublicense,
% and/or sell copies of the Software, and to permit persons to whom the
% Software is furnished to do so, subject to the following conditions:

% The above copyright notice and this permission notice shall be included in
% all copies or substantial portions of the Software.

% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
% DEALINGS IN THE SOFTWARE.

% @private
-module(hello_validate).
-export([request/2]).
-export([validate_params/3, validate_params/4]).
-export_type([json_type/0, param_type/0]).

-include_lib("yang/include/typespec.hrl").
-include("hello.hrl").
-include("internal.hrl").

-type json_type()  :: 'boolean' | 'object' | 'integer' | 'float' | 'number' | 'string' | 'list' | 'array' | 'any' | 'iso_date'.
-type param_type() :: json_type() | {enum, [atom()]}.

%% --------------------------------------------------------------------------------
%% -- API functions
-spec request(atom, #request{}) -> [term()] | {error, iodata()}.
request(Mod, Req = #request{method = Method, params = Params}) ->
    ModSpec = find_hello_info(Mod),
    try
	Fields = yang_typespec:rpc_params(Method, ModSpec),
	case hello_validate:validate_params(ModSpec, Method, params_to_proplist(Fields, Params)) of
	    {error, Code} ->
		{error, hello_proto:error_response(Req, Code)};
	    {error, Code, Msg} ->
		{error, hello_proto:error_response(Req, Code, Msg)};
	    ParamsValidated ->
		ParamsValidated
	end
    catch
	error:{badarg, _} ->
            {error, hello_proto:error_response(Req, method_not_found)};
	throw:{error, unknown_type} ->
            {error, hello_proto:error_response(Req, method_not_found)};
	throw:_ ->
	    hello_proto:error_response(Req, invalid_params, <<"">>)
    end.

params_return(Return, []) ->
    Return;
params_return({ok, Method, Params}, [{methods_as, atom}|T]) ->
    params_return({ok, binary_to_atom(Method, utf8), Params}, T);
params_return({ok, Method, Params}, [{params_as, list}|T]) ->
    params_return({ok, Method, strip_keys(Params)}, T);
params_return(Return, [_|T]) ->
    params_return(Return, T).

validate_params(TypeSpec, Method, Params) ->
    validate_params(TypeSpec, Method, -1, Params).

validate_params(TypeSpec, Method, Depth, Params) ->
    try yang_json_validate:validate(TypeSpec, {rpc, Method, input}, Depth, Params) of
	Error when element(1, Error) == error ->
	    Error;
	ParamsValidated when is_list(ParamsValidated) ->
	    #object{opts = Opts} = yang_typespec:get_type(TypeSpec, {rpc, Method, input}),
	    params_return({ok, Method, ParamsValidated}, Opts)
    catch
	throw:{error, Error} ->
	    Msg = io_lib:format("Error: ~p", [Error]),
	    {error, invalid_params, Msg};
	throw:{error, Error, EMsg} ->
	    Msg = io_lib:format("Error: ~p, EMsg: ~p", [Error, EMsg]),
	    {error, invalid_params, Msg}
    end.

%% --------------------------------------------------------------------------------
%% -- internal functions
params_to_proplist(_PInfo, {Props}) -> Props;
params_to_proplist(Fields,  Params) when is_list(Params) ->
    {Proplist, TooMany} = zip(Fields, Params, {[], false}),
    TooMany andalso throw({invalid, "superfluous parameters"}),
    lists:reverse(Proplist).

strip_keys(Proplist) ->
    [V || {_K, V} <- Proplist].

zip([], [], Result) ->
    Result;
zip([], _2, {Result, _TM}) ->
    zip([], [], {Result, true});
zip(_1, [], Result) ->
    zip([], [], Result);
zip([H1|R1], [H2|R2], {Result, TooMany}) ->
    zip(R1, R2, {[{H1, H2}|Result], TooMany}).

cb_apply(Mod, Function) ->
    cb_apply(Mod, Function, []).
cb_apply({Mod, State}, Function, Args) ->
    erlang:apply(Mod, Function, Args ++ [State]);
cb_apply(Mod, Function, Args) ->
    ct:pal("Apply: ~p~n", [{Mod, Function, Args}]),
    erlang:apply(Mod, Function, Args).

%% --------------------------------------------------------------------------------
%% -- backwards compatibility functions

module_type({Mod, _}) ->
    module_type(Mod);
module_type(Mod) ->
    atom_to_binary(Mod, utf8).

build_field(#rpc_param{name = Name, optional = Optional, description = Desc}, Type) ->
    #field{name = atom_to_binary(Name, utf8),
	   description = Desc,
	   type = Type,
	   mandatory = not Optional,
	   opts = []
	  }.

build_fields_spec(P = #rpc_param{type = string}) ->
    build_field(P, #string{});
build_fields_spec(P = #rpc_param{type = {enum, Enums}}) ->
    build_field(P, #enumeration{enum = Enums});
build_fields_spec(P = #rpc_param{type = Type}) ->
    build_field(P, {atom_to_binary(Type, utf8), []}).

build_rpc_opts(#rpc_method{params_as = list}) ->
    [{methods_as, atom},{params_as, list}];
build_rpc_opts(_) ->
    [{methods_as, atom}].

build_rpc_typespec(Mod, M = #rpc_method{name = Name, description = Desc}) ->
    Fields = [build_fields_spec(F) || F <- cb_apply(Mod, param_info, [Name])],
    #rpc{name = atom_to_binary(Name, utf8), description = Desc,
	 input = #object{name = input, fields = Fields, opts = build_rpc_opts(M)}
	}.

build_hello_info(Mod) ->
    {module_type(Mod),
     [build_rpc_typespec(Mod, RPC) || RPC <- cb_apply(Mod, method_info)]}.

find_hello_info(Mod) ->
    try
	cb_apply(Mod, hello_info)
    catch
	error:undef ->
	    build_hello_info(Mod)
    end.
