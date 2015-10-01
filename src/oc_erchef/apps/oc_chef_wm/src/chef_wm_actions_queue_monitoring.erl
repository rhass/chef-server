%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
%% ex: ts=4 sw=4 et
%%% @author Dave Parfitt <dparfitt@chef.io>
%%% @doc
%%% monitor RabbitMQ length of analytics queues
%%% @end
%% Copyright 2011-2015 Chef Software, Inc. All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%

-module(chef_wm_actions_queue_monitoring).

-ifdef(TEST).
-compile(export_all).
-endif.

-export([start_link/0]).
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3,
         status/0,
         status_for_json/0,
         is_queue_at_capacity/0,
         override_queue_at_capacity/1,
         message_dropped/0
        ]).

-behaviour(gen_server).
-define(SERVER, ?MODULE).

-record(state, {queue_at_capacity = false,
                timer,
                max_length = 0,
                last_recorded_length = 0,
                dropped_since_last_check = 0,
                total_dropped = 0
               }).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


-spec status() -> [{atom(), _}].
status() ->
    gen_server:call(?SERVER, status).

status_for_json() ->
    gen_server:call(?SERVER, status_for_json).

is_queue_at_capacity() ->
    gen_server:call(?SERVER, is_queue_at_capacity).

override_queue_at_capacity(AtCapacity) ->
    gen_server:call(?SERVER, {override_queue_at_capacity, AtCapacity}).

message_dropped() ->
    gen_server:call(?SERVER, message_dropped).

%%-------------------------------------------------------------

init([]) ->
    Interval = envy:get(oc_chef_wm, rabbitmq_queue_length_monitor_millis, pos_integer),
    {ok, TRef} = timer:send_interval(Interval, status_ping),
    {ok, #state{timer=TRef}}.

handle_call(is_queue_at_capacity, _From, #state{queue_at_capacity =
                                                QueueAtCapacity} = State) ->
    {reply, QueueAtCapacity, State};

handle_call({override_queue_at_capacity, AtCapacity}, _From, State) ->
    lager:info("Manually setting queue_at_capacity ~p", [AtCapacity]),
    {reply, ok, State#state{queue_at_capacity = AtCapacity}};

handle_call(message_dropped, _From, #state{total_dropped = TotalDropped,
                                           dropped_since_last_check = Dropped} = State) ->
  {reply, ok, State#state{total_dropped = TotalDropped + 1,
                          dropped_since_last_check = Dropped + 1}};

handle_call(status, _From, #state{queue_at_capacity = QAC,
                                  dropped_since_last_check = Dropped,
                                  max_length = ML,
                                  last_recorded_length = LL,
                                  total_dropped = Total} = State) ->
    Stats = [{queue_at_capacity,QAC},
             {dropped_since_last_check, Dropped},
             {max_length, ML},
             {last_recorded_length, LL},
             {total_dropped, Total}],
    {reply, Stats, State};
handle_call(status_for_json, _From, State) ->
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info(status_ping, State) ->
    lager:debug("Checking RabbitMQ status"),
    check_current_queue_state(State);

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{timer=Timer}) ->
    {ok, cancel} = timer:cancel(Timer),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%-------------------------------------------------------------

check_current_queue_state(State) ->
    case get_max_length() of
        undefined -> {noreply, State};
                     % max length isn't configured, or something is broken
                     % don't continue.
        MaxLength ->
            lager:info("Max Length = ~p", [MaxLength]),
            CurrentLength = get_current_length(),
            case CurrentLength of
                undefined ->
                    lager:info("No messages on queue"),
                    {noreply, State#state{dropped_since_last_check = 0}}; % no messages on the queue
                N -> lager:info("Current Length = ~p", [N]),
                     QueueAtCapacity = CurrentLength == MaxLength,
                     Ratio = CurrentLength / MaxLength,
                     case Ratio >= 0.8 of
                         true -> Pcnt = round(Ratio * 100.0),
                                 lager:warning("RabbitMQ capacity at ~p%", [Pcnt]);
                         false -> ok
                     end,
                     case QueueAtCapacity of
                         true -> lager:warning("Dropped ~p messages since last check due to queue limit exceeded",
                                               [State#state.dropped_since_last_check]);
                         false -> ok
                     end,
                     {noreply, State#state{max_length = MaxLength,
                                           last_recorded_length = N,
                                           dropped_since_last_check = 0,
                                           queue_at_capacity = QueueAtCapacity}}
            end
    end.

rabbit_mgmt_server_request(Path) ->
    User = envy:get(oc_chef_wm, rabbitmq_management_user, binary),
    Host = envy:get(oc_chef_wm, actions_host, string),
    Password = envy:get(oc_chef_wm, rabbitmq_management_password, binary),
    MgmtPort = envy:get(oc_chef_wm, rabbitmq_management_port, non_neg_integer),
    FullUrl = lists:flatten(io_lib:format('http://~s:~p~s', [Host, MgmtPort, Path])),
    ibrowse:send_req(FullUrl,
                     [], get, [], [{basic_auth, {binary_to_list(User),
                                                 binary_to_list(Password)}}]).

-spec get_max_length() -> integer() | undefined.
get_max_length() ->
    MaxResult = rabbit_mgmt_server_request("/api/policies/%2Fanalytics/max_length"),
    case MaxResult of
        {ok, "200", _, MaxLengthJson} ->
            try
                parse_max_length_response(MaxLengthJson)
            catch _Ex:_Type ->
                      lager:error("Invalid RabbitMQ response while getting queue max length"),
                      undefined
            end;
        {error, {conn_failed,_}} ->
            lager:info("Can't connect to RabbitMQ management console"),
            undefined;
        {ok, "404", _, _} ->
            lager:info("RabbitMQ max-length policy not set"),
            undefined;
        _Resp -> lager:error("Unknown response from RabbitMQ management console"),
                 undefined

    end.

-spec get_current_length() -> integer() | undefined.
get_current_length() ->
    CurrentResult = rabbit_mgmt_server_request("/api/queues/%2Fanalytics"),
    case CurrentResult of
        {error, {conn_failed,_}} ->
            lager:info("Can't connect to RabbitMQ management console"),
            undefined;
        {ok, "200", _, CurrentStatusJson} ->
            try
                parse_current_length_response(CurrentStatusJson)
            catch _:_ ->
                      lager:error("Invalid RabbitMQ response while getting queue length"),
                      undefined
            end;
        _Resp -> lager:error("Unknown response from RabbitMQ management console"),
                 undefined
    end.

-spec parse_current_length_response(binary()) -> integer() | undefined.
parse_current_length_response(Message) ->
    CurrentJSON = jiffy:decode(Message),
    % make a proplists of each queue and it's current length
    QueueLengths =
    lists:map(fun (QueueStats) -> {QS} = QueueStats,
                                    {proplists:get_value(<<"name">>, QS),
                                    proplists:get_value(<<"messages">>, QS)}
                end, CurrentJSON),
    % look for the alaska queue length
    proplists:get_value(<<"alaska">>, QueueLengths, undefined).


-spec parse_max_length_response(binary()) -> integer() | undefined.
parse_max_length_response(Message) ->
    {MaxLengthPolicy} = jiffy:decode(Message),
    {Defs} = proplists:get_value(<<"definition">>, MaxLengthPolicy),
    proplists:get_value(<<"max-length">>, Defs, undefined).

