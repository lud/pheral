-module(cowboy_pheral_fcgi).
-behaviour(cowboy_handler).
-export([init/2]).

-include_lib("eunit/include/eunit.hrl").

-type uint32() :: 0..(1 bsl 32 - 1).

-type http_req() :: cowboy_req:req().

-type fold_k_stdout_fun(Acc, NewAcc) ::
  fun((Acc, Buffer::binary() | eof, fold_k_stdout_fun(Acc, NewAcc)) -> NewAcc).

-type option() :: {name, atom()}
                | {timeout, uint32()}
                | {script_dir, iodata()}
                | {path_root, iodata()}.

-export_type([option/0]).

-record(state, {server :: pid(),
                timeout :: uint32(),
                script_dir :: iodata(),
                path_root :: iodata(),
                script_name :: iodata(),
                https :: boolean()}).

-record(cgi_head, {status  = 200 :: cowboy:http_status(),
                   type :: undefined | binary(),
                   location :: undefined | binary(),
                   headers = #{} :: cowboy:http_headers()}).

-spec init(http_req(), [option()]) ->
            {ok, http_req(), #state{}}.
init(Req, Opts) ->
  {name, Name} = lists:keyfind(name, 1, Opts),
  {script_name, ScriptName} = lists:keyfind(script_name, 1, Opts),
  {script_dir, ScriptDir} = lists:keyfind(script_dir, 1, Opts),
  Timeout = case lists:keyfind(timeout, 1, Opts) of
    {timeout, To} -> To;
    false -> 60000 end,
  PathRoot = case lists:keyfind(path_root, 1, Opts) of
    {path_root, Pr} -> Pr;
    false -> ScriptDir end,
  Https = cowboy_req:scheme(Req) =:= <<"https">>,
  FcgiPid = case Name of
    Atom when is_atom(Atom) -> whereis(Atom);
    Pid when is_pid(Pid) -> Pid
  end,
  State = #state{server = FcgiPid,
             timeout = Timeout,
             script_dir = ScriptDir,
             path_root = PathRoot,
             script_name = ScriptName,
             https = Https},
  handle_script(Req, State).

-spec handle_script(http_req(), #state{}) -> {ok, http_req(), #state{}}.
handle_script(Req, State) ->
  #state{script_name = ScriptName, script_dir = ScriptDir} = State,
  CGIParams = [
    {<<"SCRIPT_NAME">>, ScriptName},
    {<<"SCRIPT_FILENAME">>, [ScriptDir, $/, ScriptName]},
    {<<"PATH_TRANSLATED">>,<<>>}
  ],
  handle_req(Req, State, CGIParams).

-spec handle_req(http_req(), #state{}, [{binary(), iodata()}]) ->
                  {ok, http_req(), #state{}}.
handle_req(Req,
           State = #state{server = Server,
                          timeout = Timeout,
                          https = Https},
           CGIParams) ->
  Method = cowboy_req:method(Req),
  Version = cowboy_req:version(Req),
  RawQs = cowboy_req:qs(Req),
  RawHost = cowboy_req:host(Req),
  Port = cowboy_req:port(Req),
  % PHP's REQUEST_URI is only from the path section
  ReqUri = cowboy_req:uri(Req, #{scheme => undefined, host => undefined}),
  Headers = cowboy_req:headers(Req),
  {Address, _Port} = cowboy_req:peer(Req),
  AddressStr = inet_parse:ntoa(Address),
  % @todo Implement correctly the following parameters:
  % - AUTH_TYPE = auth-scheme token
  % - REMOTE_USER = user-ID token
  CGIParams1 = case Https of
    true -> [{<<"HTTPS">>, <<"1">>}|CGIParams];
    false -> CGIParams end,
  CGIParams2 = [{<<"GATEWAY_INTERFACE">>, <<"CGI/1.1">>},
                {<<"QUERY_STRING">>, RawQs},
                {<<"REMOTE_ADDR">>, AddressStr},
                {<<"REQUEST_URI">>, ReqUri},
                {<<"REMOTE_HOST">>, AddressStr},
                {<<"REQUEST_METHOD">>, Method},
                {<<"SERVER_NAME">>, RawHost},
                {<<"SERVER_PORT">>, integer_to_list(Port)},
                {<<"SERVER_PROTOCOL">>, protocol(Version)},
                {<<"SERVER_SOFTWARE">>, <<"Cowboy">>} |
                CGIParams1],
  CGIParams3 = params(Headers, CGIParams2),
  % io:format("CGIParams3 ~p~n", [CGIParams3]),
  case ex_fcgi:begin_request(Server, responder, CGIParams3, Timeout) of
    error ->
      Req2 = cowboy_req:reply(502, Req),
      {ok, Req2, State};
    {ok, Ref} ->
      {ok, Body, Req3} = handle_req_read_body(Req, <<>>),
      ex_fcgi:send(Server, Ref, Body),
      Fun = fun decode_cgi_head/3,
      Req4 = case fold_k_stdout(#cgi_head{}, <<>>, Fun, Ref) of
        {Head, Rest, Fold} ->
          case acc_body([], Rest, Fold) of
            error ->
              cowboy_req:reply(502, Req3);
            timeout ->
              cowboy_req:reply(504, Req3);
            CGIBody ->
              send_response(Req3, Head, CGIBody)
          end;
        error ->
          cowboy_req:reply(502, Req3);
        timeout ->
          cowboy_req:reply(504, Req3)
      end,
      {ok, Req4, State}
  end.

-spec handle_req_read_body(http_req(), binary()) -> {ok, binary(), http_req()}.
handle_req_read_body(Req0, Acc) ->
  case cowboy_req:read_body(Req0) of
    {ok, Data, Req} -> {ok, << Acc/binary, Data/binary >>, Req};
    {more, Data, Req} -> handle_req_read_body(Req, << Acc/binary, Data/binary >>)
  end.

-spec path_info(PathInfo::cowboy_router:tokens(),
                Path::cowboy_router:tokens()) ->
                 {CGIPathInfo::iolist(),
                  ScriptName::cowboy_router:tokens()}.
path_info(PathInfo, Path) ->
  path_info(lists:reverse(PathInfo), lists:reverse(Path), []).

-spec path_info(PathInfo::cowboy_router:tokens(),
                Path::cowboy_router:tokens(),
                CGIPathInfo::iolist()) ->
                  {CGIPathInfo::iolist(),
                   ScriptName::cowboy_router:tokens()}.
path_info([Segment|PathInfo], [Segment|Path], CGIPathInfo) ->
  path_info(PathInfo, Path, [$/, Segment|CGIPathInfo]);
path_info([], Path, CGIPathInfo) ->
  {CGIPathInfo, lists:reverse(Path)}.

-spec protocol(cowboy:http_version()) -> binary().
protocol(Version) when is_atom(Version) ->
  atom_to_binary(Version, utf8).

-spec params(cowboy:http_headers(), [{binary(), iodata()}]) -> [{binary(), iodata()}].
params(Params, Acc) ->
  F = fun (Name, Value, Acc1) ->
    ParamName = param(Name),
    case Acc1 of
      [{ParamName, AccValue} | Acc2] ->
        % Value is counter-intuitively prepended to AccValue
        % because Cowboy accumulates headers in reverse order.
        [{ParamName, [Value, value_sep(Name) | AccValue]} | Acc2];
      _ ->
        [{ParamName, Value} | Acc1]
    end
  end,
  maps:fold(F, Acc, Params).

-spec value_sep(binary()) -> char().
value_sep(<<"cookie">>) ->
  % Accumulate cookies using a semicolon because at least one known FastCGI
  % implementation (php-fpm) doesn't understand comma-separated cookies.
  $;;
value_sep(_Header) ->
  $,.

-spec param(binary()) -> binary().
param(<<"accept">>) ->
  <<"HTTP_ACCEPT">>;
param(<<"accept-charset">>) ->
  <<"HTTP_ACCEPT_CHARSET">>;
param(<<"accept-encoding">>) ->
  <<"HTTP_ACCEPT_ENCODING">>;
param(<<"accept-language">>) ->
  <<"HTTP_ACCEPT_LANGUAGE">>;
param(<<"cache-control">>) ->
  <<"HTTP_CACHE_CONTROL">>;
param(<<"content-base">>) ->
  <<"HTTP_CONTENT_BASE">>;
param(<<"content-encoding">>) ->
  <<"HTTP_CONTENT_ENCODING">>;
param(<<"content-language">>) ->
  <<"HTTP_CONTENT_LANGUAGE">>;
param(<<"content-length">>) ->
  <<"CONTENT_LENGTH">>;
param(<<"content-md5">>) ->
  <<"HTTP_CONTENT_MD5">>;
param(<<"content-range">>) ->
  <<"HTTP_CONTENT_RANGE">>;
param(<<"content-type">>) ->
  <<"CONTENT_TYPE">>;
param(<<"cookie">>) ->
  <<"HTTP_COOKIE">>;
param(<<"etag">>) ->
  <<"HTTP_ETAG">>;
param(<<"from">>) ->
  <<"HTTP_FROM">>;
param(<<"if-modified-since">>) ->
  <<"HTTP_IF_MODIFIED_SINCE">>;
param(<<"if-match">>) ->
  <<"HTTP_IF_MATCH">>;
param(<<"if-none-match">>) ->
  <<"HTTP_IF_NONE_MATCH">>;
param(<<"if-range">>) ->
  <<"HTTP_IF_RANGE">>;
param(<<"if-unmodified-since">>) ->
  <<"HTTP_IF_UNMODIFIED_SINCE">>;
param(<<"location">>) ->
  <<"HTTP_LOCATION">>;
param(<<"pragma">>) ->
  <<"HTTP_PRAGMA">>;
param(<<"range">>) ->
  <<"HTTP_RANGE">>;
param(<<"referer">>) ->
  <<"HTTP_REFERER">>;
param(<<"user-agent">>) ->
  <<"HTTP_USER_AGENT">>;
param(<<"warning">>) ->
  <<"HTTP_WARNING">>;
param(<<"x-forwarded-for">>) ->
  <<"HTTP_X_FORWARDED_FOR">>;
param(Name) when is_binary(Name) ->
  <<"HTTP_", (<< <<(param_char(C))>> || <<C>> <= Name >>)/binary>>.

-spec param_char(char()) -> char().
param_char($a) -> $A;
param_char($b) -> $B;
param_char($c) -> $C;
param_char($d) -> $D;
param_char($e) -> $E;
param_char($f) -> $F;
param_char($g) -> $G;
param_char($h) -> $H;
param_char($i) -> $I;
param_char($j) -> $J;
param_char($k) -> $K;
param_char($l) -> $L;
param_char($m) -> $M;
param_char($n) -> $N;
param_char($o) -> $O;
param_char($p) -> $P;
param_char($q) -> $Q;
param_char($r) -> $R;
param_char($s) -> $S;
param_char($t) -> $T;
param_char($u) -> $U;
param_char($v) -> $V;
param_char($w) -> $W;
param_char($x) -> $X;
param_char($y) -> $Y;
param_char($z) -> $Z;
param_char($-) -> $_;
param_char(Ch) -> Ch.

-spec fold_k_stdout(Acc, binary(), fold_k_stdout_fun(Acc, NewAcc),
                    reference()) ->
                     NewAcc | error | timeout.
fold_k_stdout(Acc, Buffer, Fun, Ref) ->
  receive Msg ->
    fold_k_stdout(Acc, Buffer, Fun, Ref, Msg)
  end.

-spec fold_k_stdout(Acc, binary(), fold_k_stdout_fun(Acc, NewAcc),
                    reference(), term()) ->
                     NewAcc | error | timeout.
fold_k_stdout(Acc, Buffer, Fun, Ref, {ex_fcgi, Ref, Messages}) ->
  fold_k_stdout2(Acc, Buffer, Fun, Ref, Messages);
fold_k_stdout(_Acc, _Buffer, _Fun, Ref, {ex_fcgi_timeout, Ref}) ->
  timeout;
fold_k_stdout(Acc, Buffer, Fun, Ref, _Msg) ->
  fold_k_stdout(Acc, Buffer, Fun, Ref).

-spec fold_k_stdout2(Acc, binary(), fold_k_stdout_fun(Acc, NewAcc),
                     reference(), [ex_fcgi:message()]) ->
                      NewAcc | error | timeout.
fold_k_stdout2(Acc, Buffer, Fun, _Ref, [{stdout, eof} | _Messages]) ->
  fold_k_stdout2(Acc, Buffer, Fun);
fold_k_stdout2(Acc, Buffer, Fun, Ref, [{stdout, NewData} | Messages]) ->
  Cont = fun (NewAcc, Rest, NewFun) ->
    fold_k_stdout2(NewAcc, Rest, NewFun, Ref, Messages) end,
  Fun(Acc, <<Buffer/binary, NewData/binary>>, Cont);
fold_k_stdout2(Acc, Buffer, Fun, _Ref,
              [{end_request, _CGIStatus, _AppStatus} | _Messages]) ->
  fold_k_stdout2(Acc, Buffer, Fun);
fold_k_stdout2(Acc, Buffer, Fun, Ref, [_Msg | Messages]) ->
  fold_k_stdout2(Acc, Buffer, Fun, Ref, Messages);
fold_k_stdout2(Acc, Buffer, Fun, Ref, []) ->
  fold_k_stdout(Acc, Buffer, Fun, Ref).

-spec fold_k_stdout2(Acc, binary(), fold_k_stdout_fun(Acc, NewAcc)) ->
                      NewAcc | error | timeout.
fold_k_stdout2(Acc, <<>>, Fun) ->
  Cont = fun (_NewAcc, _NewBuffer, _NewFun) -> error end,
  Fun(Acc, eof, Cont);
fold_k_stdout2(_Acc, _Buffer, _Fun) ->
  error.

-spec decode_cgi_head(#cgi_head{}, binary() | eof,
                      fold_k_stdout_fun(#cgi_head{},
                                        #cgi_head{} | error | timeout)) ->
                       #cgi_head{} | error | timeout.
decode_cgi_head(_Head, eof, _More) ->
  error;
decode_cgi_head(Head, Data, More) ->
  case erlang:decode_packet(httph_bin, Data, []) of
    {ok, {http_header, Int, Field, Atom, Value}, Rest} when is_atom(Field) ->
      % httph_bin decoding will return recognized HTTP header field names as atoms.
      % Convert them to binary so we can use them with cowboy.
      decode_cgi_head(Head, Rest, More, {http_header, Int, atom_to_binary(Field, utf8), Atom, Value});
    {ok, Packet, Rest} ->
      decode_cgi_head(Head, Rest, More, Packet);
    {more, _} ->
      More(Head, Data, fun decode_cgi_head/3);
    _ ->
      error end.

-define(decode_default(Head, Rest, More, Field, Default, Value),
  case Head#cgi_head.Field of
    Default ->
      decode_cgi_head(Head#cgi_head{Field = Value}, Rest, More);
    _ ->
      % Decoded twice the same CGI header.
      error end).

-spec decode_cgi_head(#cgi_head{}, binary(),
                      fold_k_stdout_fun(#cgi_head{},
                                        #cgi_head{} | error | timeout),
                      term()) -> #cgi_head{} | error | timeout.
decode_cgi_head(Head, Rest, More, {http_header, _, <<"Status">>, _, Value}) ->
  ?decode_default(Head, Rest, More, status, 200, Value);
decode_cgi_head(Head, Rest, More,
                {http_header, _, <<"Content-Type">>, _, Value}) ->
  ?decode_default(Head, Rest, More, type, undefined, Value);
decode_cgi_head(Head, Rest, More, {http_header, _, <<"Location">>, _, Value}) ->
  ?decode_default(Head, Rest, More, location, undefined, Value);
decode_cgi_head(Head, Rest, More,
                {http_header, _, << "X-CGI-", _NameRest >>, _, _Value}) ->
  % Dismiss any CGI extension header.
  decode_cgi_head(Head, Rest, More);
decode_cgi_head(Head = #cgi_head{headers = Headers}, Rest, More,
                {http_header, _, Name, _, Value}) ->
  NewHead = Head#cgi_head{headers = maps:put(Name, Value, Headers)},
  decode_cgi_head(NewHead, Rest, More);
decode_cgi_head(Head, Rest, More, http_eoh) ->
  {Head, Rest, More};
decode_cgi_head(_Head, _Rest, _Name, _Packet) ->
  error.

-spec acc_body([binary()], binary() | eof,
               fold_k_stdout_fun([binary()], [binary()]) | error | timeout) ->
                [binary()] | error | timeout.
acc_body(Acc, eof, _More) ->
  lists:reverse(Acc);
acc_body(Acc, Buffer, More) ->
  More([Buffer | Acc], <<>>, fun acc_body/3).

-spec send_response(http_req(), #cgi_head{}, [binary()]) -> http_req().
send_response(Req, #cgi_head{location = <<$/, _/binary>>}, _Body) ->
  % @todo Implement 6.2.2. Local Redirect Response.
  cowboy_req:reply(502, Req);
send_response(Req, Head = #cgi_head{location = undefined}, Body) ->
  % 6.2.1. Document Response.
  send_document(Req, Head, Body);
send_response(Req, Head, Body) ->
  % 6.2.3. Client Redirect Response.
  % 6.2.4. Client Redirect Response with Document.
  send_redirect(Req, Head, Body).

-spec send_document(http_req(), #cgi_head{}, [binary()]) -> http_req().
send_document(Req, #cgi_head{type = undefined}, _Body) ->
  cowboy_req:reply(502, Req);
send_document(Req, #cgi_head{status = Status, type = Type, headers = Headers},
              Body) ->
  % PHP adds a Content-Lenght header (CamelCase) When I test with curl or nodejs
  % as a http client, cowboy adds a duplicate content-length header (lowercase)
  % with valuf of = 0, which is incorrect. With HTTPoison/hackney, the duplicate
  % header is correct.
  % So we discard the one with camel case and set the one with lowercase.
  Headers2 = case maps:get(<<"Content-Length">>, Headers, undefined) of
    undefined -> Headers;
    ContentLenght ->
      Headers1 = maps:remove(<<"Content-Length">>, Headers),
      maps:put(<<"content-length">>, ContentLenght, Headers1)
  end,
  io:format("Send document headers ~p~n", [Headers2]),
  reply(Req, Body, Status, Type, Headers2).

-spec send_redirect(http_req(), #cgi_head{}, [binary()]) -> http_req().
send_redirect(Req, #cgi_head{status = Status = <<$3, _/binary>>,
                             type = Type,
                             location = Location,
                             headers = Headers}, Body) ->
  reply(Req, Body, Status, Type, maps:put(<<"Location">>, Location, Headers));
send_redirect(Req, #cgi_head{type = Type,
                             location = Location,
                             headers = Headers}, Body) ->
  reply(Req, Body, 302, Type, maps:put(<<"Location">>, Location, Headers)).

-spec reply(http_req(), [binary()], cowboy:http_status(), undefined | binary(),
            cowboy:http_headers()) -> http_req().
%% @todo Filter headers like Content-Length.
reply(Req, Body, Status, undefined, Headers) ->
  cowboy_req:reply(Status, Headers, Body, Req);
reply(Req, Body, Status, Type, Headers) ->
  io:format("pheral:reply Status ~p~n", [Status]),
  io:format("pheral:reply Headers ~p~n", [Headers]),
  cowboy_req:reply(Status, maps:put(<<"Content-Type">>, Type, Headers), Body, Req).

-ifdef(TEST).

param_test() ->
  ?assertEqual(<<"HTTP_X_NON_STANDARD_HEADER">>,
               param(<<"X-Non-Standard-Header">>)).

-endif.
