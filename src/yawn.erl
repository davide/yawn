%%% File: yawn.erl
%%% @author Davide Marquês <nesrait@gmail.com>
%%% @since 15 Dec 2008 by Davide Marquês <nesrait@gmail.com>
%%% @doc Yawn - "Yaws Nest". 
%%% <p>An easy way to deploy various webapps on a yaws server.</p>
%%% 
%%% <p>When I started using Yaws one of the things I first tried to do was to
%%% deploy two erlyweb webapps on the same server. The problem was that
%%% erlyweb read an unique appname opaque variable, so that stopped me
%%% from simply setting up two appmods.</p>
%%% <p>The only solution seemed to be using Yapps and registering the
%%% two webapps.</p>
%%% <p>The docs state: "In order to make a "yapp" we need to know how to
%%% make an ordinary Erlang application".</p>
%%% <p>One word: overkill! This is just too much to ask for someone trying to
%%% get their feets wet with Yaws/Erlang.
%%% A person should be able to play around for a bit before *having to* plung
%%% into OTP.</p>
%%% <p>I disliked using Yapps so much (not that it's not good, I was just that
%%% much of a noob :P) that I ended up trying to hack erlyweb to inject
%%% sanboxing abilities (using yaws_vdir as an helper).</p>
%%%<p>After some iterations I realized part of what what I'd done could be
%%% refactored. And so Yawn was born! :)</p>
%%% <p>Yaws' main advantages are that it enables 1) docroot switching; and
%%% 2) opaque variables redefinition, on a per-appmod basis - like Yapp does -
%%% but with a simpler to install and use (for noobs at least) approach.</p>
%%% 
%%% Nothing better than a quick example to show how it works!
%%% Starting of with this server configuration:
%%% &lt;server localhost&gt;
%%%         port = 80
%%%         listen = 0.0.0.0
%%%         docroot = www
%%% 	appmods = &lt;"/noe", erlyweb&gt;
%%%         &lt;opaque&gt;
%%% 		yawn = "/noe, appname = noe, docroot = c:/erlyapps/noe/www, key1 = value1, key2 = value2"
%%%         &lt;/opaque&gt;
%%% 	arg_rewrite_mod = yawn
%%% &lt;/server&gt;
%%% 
%%% If yaws gets a request for a page under http://localhost/noe/ it will rewrite
%%% the request into:
%%% &lt;server localhost&gt;
%%%         port = 80
%%%         listen = 0.0.0.0
%%%         docroot = c:/erlyapps/noe/www
%%% 	appmods = &lt;"/noe", erlyweb&gt;
%%%         &lt;opaque&gt;
%%% 		yawn = "/noe, docroot = c:/erlyapps/noe/www, key1 = value1, key2 = value2"
%%% 		key1 = "value1"
%%% 		key2 = "value2"
%%%         &lt;/opaque&gt;
%%% 	arg_rewrite_mod = yawn
%%% &lt;/server&gt;
%%% Additionally, it will call yawn_vdir before returning #arg to yaws.
%%%
%%% <p>The yawn opaque variable values should start with the appmod
%%% URI followed by a comma and a list of comma separated "key = value"
%%% pairs (of which only the docroot key is mandatory). This can change in the future!</p>
%%%
%%% <p>This module only exists because I was able to study yapp,
%%% yaws_vdir and yaws' source code. A special thanks to the authors! ;)
%%%

-module(yawn).
-author('nesrait@gmail.com').

-include_lib("yaws/include/yaws_api.hrl").
-include_lib("yaws/include/yaws.hrl").

-export([arg_rewrite/1]).

-define(opaque_variable, ?MODULE_STRING).
-define(appmod_data_separator, ",").
-define(appmod_properties_separator, "=").

arg_rewrite(Arg) ->
    % Rebuild the request according to the matched appmods
    Arg1 = match_hostname(Arg),
    % But let VDirs override whatever they need to get file serving right
    Arg2 = yawn_vdir:arg_rewrite(Arg1),
    Arg2.

match_hostname(Arg) ->
	case get_virtualhost(Arg) of
		undefined ->
			log(info, "No virtualhost match.~n", []),
			Arg;
		Server -> match_appmods(Arg, Server)
	end.

%% @spec get_virtualhost(Arg::yaws_arg()) -> {ServId,Port,Appmods,Opaque}
get_virtualhost(Arg) ->
    {ok, _Gconf, Sconfs} = yaws_api:getconf(),
    Host = (Arg#arg.headers)#headers.host,
    Servers = [{Host, Port, AM, OP} ||
			#sconf{servername=Host2, port=Port, appmods=AM, opaque=OP} <- lists:flatten(Sconfs),
			Host2 =:= Host],
    case Servers of
	[S1] -> S1;
	[S1|_] -> S1;
	_ -> undefined
    end.

% Find the most specific match for the request path within the various Appmod URIs
match_appmods(Arg, {_Host, _Port, AppMods, Opaque}) ->
    case collect_appmod_uris(AppMods) of
	[] ->
		log(info, "No appmods defined on server config.~n", []),
		Arg;
	AppModURIs ->
		Request = get_request_path(Arg),
		case get_longest_matching_path(AppModURIs, Request) of
			"" ->
				log(info, "None of the AppMod URIs match the request path: ~p.~n", [Request]),
				Arg;
			MatchedURI ->
				match_opaque_config(Arg, MatchedURI, Opaque)
		end
    end.

collect_appmod_uris(AppMods) ->
	lists:foldl(fun({URI, _}, Acc) -> [URI|Acc] end, [], AppMods).

get_request_path(Arg) ->
    {abs_path, Path} = (Arg#arg.req)#http_request.path,
    Path.


% The AppModURI and Opaque variable URI must be the same
match_opaque_config(Arg, _, []) -> Arg;
match_opaque_config(Arg, AppModURI, [{?opaque_variable, Data}|R]) ->
    case get_config_from_text(Data) of
	undefined -> Arg;
	[AppModURI, ConfigText] -> % SUCCESS
		process_appmod_config(Arg, AppModURI, ConfigText);
	_ ->
		match_opaque_config(Arg, AppModURI, R)
    end;
match_opaque_config(Arg, URI, [_|R]) ->
	match_opaque_config(Arg, URI, R).

get_config_from_text(Text) ->
    case string:tokens(Text, ?appmod_data_separator) of
	[Uri|Rest] ->
		HasSpaces = lists:any(fun(C) -> C=:=32 end, Uri),
		if (HasSpaces) ->
			display_config_error({spaces_in_uri, Uri}),
			undefined;
		   true -> [Uri, Rest]
		end;
	_ ->
		display_config_error({nomatch_config_uri, Text}, show_expected),
		undefined
    end.

process_appmod_config(Arg, AppModURI, ConfigText) ->
    case get_properties_from_text(AppModURI, ConfigText, []) of
	undefined -> Arg;
	Props ->
		Docroot = proplists:get_value("docroot", Props),
		if (Docroot =:= undefined) ->
			display_config_error({missing_docroot}, show_expected),
			Arg;
		   true ->
			% Example Scenario:
			%   - AppModURI = /ems
			%   - Docroot = c:/yaws/erlyapps/ems/www
			%   - Request = /ems/index.html
			log(info, "Activating appmod: ~p.~n", [AppModURI]),
			
			% We'll inject all the configuration properties into the request opaque
			Arg1 = Arg#arg{opaque=(Props ++ Arg#arg.opaque)},
			
			% We'll check for static files first!
			Request = get_request_path(Arg),
			RelativePath = Request -- AppModURI,
			Path = filename:absname(Docroot ++ "/" ++ RelativePath),
			case (filelib:is_dir(Path) orelse filelib:is_regular(Path)) of
				true ->
					% We'll set up a vdir for serving the file
					DocMount =
						case string:right(AppModURI, 1) of
							"/" -> AppModURI;
							_ -> AppModURI ++ "/"
						end,
					
					setup_yaws_vdir(DocMount, Docroot),
					
					Arg1#arg{docroot=Docroot, docroot_mount=DocMount}
					;
				false ->
					Arg1
			end
		end
    end.
	
get_properties_from_text(_Uri, [], Acc) -> Acc;
get_properties_from_text(Uri, [Text|R], Acc) ->
	case string:tokens(string:strip(Text), ?appmod_properties_separator) of
		[Key, Value] ->
			Key1 = string:strip(Key),
			Value1 = string:strip(Value),
			get_properties_from_text(Uri, R, [{Key1, Value1}|Acc]);
		_ ->
			display_config_error({invalid_property_list, Text}, show_expected),
			undefined
	end.

%% Add Vdir using Yaws' process dictionary.
%% Code adapted from yaws_vdir.
setup_yaws_vdir(DocMount, Docroot) ->
    VDir = {"vdir", DocMount ++ " " ++ Docroot},
    SC = get(sc),
    Opaque = [VDir] ++ SC#sconf.opaque,
    SC2 = SC#sconf{docroot=Docroot, opaque = Opaque},
    put(sc, SC2).

%% Given a list of AppModURIs and a Request Path this function
%% will return the longest matching AppModURI.
%% Code adapted/simplified from yaws_server:vdirpath/3.
get_longest_matching_path(Strings, SearchString) ->
    SearchSegs = string:tokens(SearchString, "/"),
    {_, MatchedURI } =
	lists:foldl(
	    fun(URI, {SearchSegs1, LongestSoFar}=Acc) ->
		URISegs = string:tokens(URI, "/"),
		case lists:prefix(URISegs, SearchSegs1) of
		   true ->
			if length(URI) > length(LongestSoFar) ->
				{SearchSegs1, URI};
			   true ->
				Acc
			end;
		   false ->
			Acc
		end
	    end,
	    {SearchSegs, ""}, Strings),
	
    MatchedURI.

display_config_error(Reason) ->
	log(error, "Invalid config! ~p~n", [Reason]).
	
display_config_error(Reason, show_expected) ->
	log(error, "Invalid config! ~p~nExpected: \"AppModURI, docroot <docroot> [, property = property_value ]\"~n", [Reason]).

%% @spec log(Level, FormatStr::string(), Args) -> void()
%%   Level = error | warning | info | debug
%%   Args = [term()]
%% @doc Yapp interface to the error_logger.
-ifdef(debug).
log(debug, FormatStr, Args) ->
    gen_event:notify(error_logger, {debug_msg, group_leader(), {self(), ?MODULE_STRING ++ ": " ++ FormatStr, Args}});
log(info, FormatStr, Args) ->
    error_logger:info_msg( ?MODULE_STRING ++ ": " ++ FormatStr, Args);
log(warning, FormatStr, Args) ->
    error_logger:warning_msg(?MODULE_STRING ++ ": " ++ FormatStr, Args);
log(error, FormatStr, Args) ->
    error_logger:error_msg(?MODULE_STRING ++ ": " ++ FormatStr, Args);
log(Level, FormatStr, Args) ->
    error_logger:error_msg(?MODULE_STRING ++ ": " ++ "Unknown logging level ~p  ," ++ FormatStr,[Level|Args]).
-else.
log(debug, _FormatStr, _Args) -> true;
log(info, _FormatStr, _Args) -> true;
log(warning, _FormatStr, _Args) -> true;
log(error, FormatStr, Args) ->
    error_logger:error_msg(?MODULE_STRING ++ ": " ++ FormatStr, Args);
log(Level, FormatStr, Args) ->
    error_logger:error_msg(?MODULE_STRING ++ ": " ++ "Unknown logging level ~p  ," ++ FormatStr,[Level|Args]).
-endif.
