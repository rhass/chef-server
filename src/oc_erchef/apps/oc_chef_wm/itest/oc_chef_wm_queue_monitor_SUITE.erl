%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
%% ex: ts=4 sw=4 et
%% @author Dave Parfitt <dparfitt@chef.io>
%%
%% Copyright 2013-2015 Chef, Inc. All Rights Reserved.
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

-module(oc_chef_wm_queue_monitor_SUITE).

-include_lib("common_test/include/ct.hrl").
-include("chef_types.hrl").
-include("oc_chef_types.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile([export_all, {parse_transform, lager_transform}]).

%-define(ORG_AUTHZ_ID, <<"10000000000000000000000000000000">>).
%-define(AUTHZ_ID, <<"00000000000000000000000000000001">>).
%-define(CLIENT_NAME, <<"test-client">>).



-define(QUEUE_LENGTH_REQ, "http://localhost:15672/api/queues/%2Fanalytics").
-define(MAX_LENGTH_REQ, "http://localhost:15672/api/policies/%2Fanalytics/max_length").

-define(EMPTY_STATUS,  [{queue_at_capacity,false},
                        {dropped_since_last_check,0},
                        {max_length,0},
                        {last_recorded_length,0},
                        {total_dropped,0}] ).

init_per_suite(Config) ->
    application:set_env(oc_chef_wm, rabbitmq_queue_length_monitor_millis, 10000),
    application:set_env(oc_chef_wm, rabbitmq_management_user, <<"foo">>),
    application:set_env(oc_chef_wm, actions_host, "localhost"),
    application:set_env(oc_chef_wm, rabbitmq_management_password, <<"bar">>),
    application:set_env(oc_chef_wm, rabbitmq_management_port, 15672),
%    setup_helper:base_init_per_suite([{org_name, <<"org">>},
%                                   {org_authz_id, ?ORG_AUTHZ_ID},
%                                   {authz_id, ?AUTHZ_ID},
%                                   {client_name, ?CLIENT_NAME}
%                                   | Config]).
    Config.

end_per_suite(_Config) ->
    ok.
    %setup_helper:base_end_per_suite(Config).

all() ->
    [
    max_length_not_set,
    max_length_set_no_queue_bound,
    max_length_set_queue_bound_no_messages,
    max_length_set_queue_bound_some_messages,
    drop_messages_no_overload,
    drop_messages_and_reset_no_overload,
    drop_messages_overload,
    drop_messages_overload_and_reset
    ].

init_per_testcase(_, Config) ->
    Config.


load_json(Config, Filename) ->
    %ct:pal("Loading json from ~p", [Filename]),
    DataDir = ?config(data_dir, Config),
    Path = filename:join(DataDir, Filename),
    {ok, File} = file:read_file(Path),
    binary_to_list(File).

max_length_json(Config) ->
    load_json(Config, "valid_max_length.json").

no_messages_json(Config) ->
    load_json(Config, "no_messages.json").


some_message_json(Config) ->
    load_json(Config, "some_messages.json").

at_capacity_json(Config) ->
    load_json(Config, "at_capacity.json").


% generate a dummy ibrowse response using the given StatusCode and Content
dummy_response(StatusCode, Content) ->
                            {ok,StatusCode,
                            [{"Content-Type","application/json"}],
                            Content}.


% meck the RabbitMQ management api endpoints for max_length and current queue
% length
meck_response(MaxLengthStatus, MaxLengthContent,
              QueueLengthStatus, QueueLengthContent) ->
    meck:new(ibrowse),
    meck:expect(ibrowse, send_req,
        fun(Url, _, _, _, _) ->
            %ct:pal("IBROWSE -> ~p", [Url]),
            case Url of
                ?QUEUE_LENGTH_REQ -> dummy_response(QueueLengthStatus, QueueLengthContent);
                ?MAX_LENGTH_REQ -> dummy_response(MaxLengthStatus, MaxLengthContent)
            end
            end).


% maximum length has been set, no state should be changed
max_length_not_set(_) ->
    meck_response("404", "", "404", ""),
    {ok, _QMPid} = chef_wm_actions_queue_monitoring:start_link(),
    chef_wm_actions_queue_monitoring:check_current_state(),

    %% checking max_length returns [], so state should be "empty"
    ?EMPTY_STATUS = chef_wm_actions_queue_monitoring:status(),
    meck:unload(ibrowse),
    ok.


% maximum length has been configured, however a queue isn't bound
% to the /analytics exchange
max_length_set_no_queue_bound(Config) ->
    meck_response("200", max_length_json(Config), "404", ""),
    {ok, _QMPid} = chef_wm_actions_queue_monitoring:start_link(),
    chef_wm_actions_queue_monitoring:check_current_state(),

    ?EMPTY_STATUS = chef_wm_actions_queue_monitoring:status(),
    meck:unload(ibrowse),
    ok.


% maximum length has been configured, a queue is bound to the exchange.
% no messages are available to read
max_length_set_queue_bound_no_messages(Config) ->
    meck_response("200",  max_length_json(Config), "200", no_messages_json(Config)),
    {ok, _QMPid} = chef_wm_actions_queue_monitoring:start_link(),
    chef_wm_actions_queue_monitoring:check_current_state(),

    [{queue_at_capacity,false},
                        {dropped_since_last_check,0},
                        {max_length,99},
                        {last_recorded_length,0},
                        {total_dropped,0}]
    = chef_wm_actions_queue_monitoring:status(),
    meck:unload(ibrowse),
    ok.


% maximum length has been configured, a queue is bound to the exchange.
% 7 messages are available to read
max_length_set_queue_bound_some_messages(Config) ->
    meck_response("200", max_length_json(Config), "200", some_message_json(Config)),
    {ok, _QMPid} = chef_wm_actions_queue_monitoring:start_link(),
    chef_wm_actions_queue_monitoring:check_current_state(),

    [{queue_at_capacity,false},
                        {dropped_since_last_check,0},
                        {max_length,99},
                        {last_recorded_length,7},
                        {total_dropped,0}]
        = chef_wm_actions_queue_monitoring:status(),
    meck:unload(ibrowse),
    ok.


% maximum length has been configured, a queue is bound to the exchange.
% 7 messages are available to read
% 2 messages will be dropped
drop_messages_no_overload(Config) ->
    meck_response("200", max_length_json(Config), "200", some_message_json(Config)),
    {ok, _QMPid} = chef_wm_actions_queue_monitoring:start_link(),
    chef_wm_actions_queue_monitoring:check_current_state(),

    chef_wm_actions_queue_monitoring:message_dropped(),
    chef_wm_actions_queue_monitoring:message_dropped(),

    [{queue_at_capacity,false},
                        {dropped_since_last_check,2},
                        {max_length,99},
                        {last_recorded_length,7},
                        {total_dropped,2}]
        = chef_wm_actions_queue_monitoring:status(),
    meck:unload(ibrowse),
    ok.


% maximum length has been configured, a queue is bound to the exchange.
% 7 messages are available to read
% 2 messages will be dropped
% recheck queue status which clears dropped_since_last_check
drop_messages_and_reset_no_overload(Config) ->
    meck_response("200", max_length_json(Config), "200", some_message_json(Config)),
    {ok, _QMPid} = chef_wm_actions_queue_monitoring:start_link(),
    chef_wm_actions_queue_monitoring:check_current_state(),

    chef_wm_actions_queue_monitoring:message_dropped(),
    chef_wm_actions_queue_monitoring:message_dropped(),
    %% calling check_current_state() will set the dropped_since_last_check to 0
    chef_wm_actions_queue_monitoring:check_current_state(),

    [{queue_at_capacity,false},
                        {dropped_since_last_check,0},
                        {max_length,99},
                        {last_recorded_length,7},
                        {total_dropped,2}]
        = chef_wm_actions_queue_monitoring:status(),
    meck:unload(ibrowse),
    ok.



% maximum length has been configured, a queue is bound to the exchange.
% 99 messages are available to read
% 2 messages will be dropped
drop_messages_overload(Config) ->
    meck_response("200", max_length_json(Config), "200", at_capacity_json(Config)),
    {ok, _QMPid} = chef_wm_actions_queue_monitoring:start_link(),
    chef_wm_actions_queue_monitoring:check_current_state(),

    chef_wm_actions_queue_monitoring:message_dropped(),
    chef_wm_actions_queue_monitoring:message_dropped(),

    [{queue_at_capacity,true},
                        {dropped_since_last_check,2},
                        {max_length,99},
                        {last_recorded_length,99},
                        {total_dropped,2}]
        = chef_wm_actions_queue_monitoring:status(),
    meck:unload(ibrowse),
    ok.


% maximum length has been configured, a queue is bound to the exchange.
% 99 messages are available to read
% 2 messages will be dropped
% recheck queue status which clears dropped_since_last_check
drop_messages_overload_and_reset(Config) ->
    meck_response("200", max_length_json(Config), "200", at_capacity_json(Config)),
    {ok, _QMPid} = chef_wm_actions_queue_monitoring:start_link(),
    chef_wm_actions_queue_monitoring:check_current_state(),

    chef_wm_actions_queue_monitoring:message_dropped(),
    chef_wm_actions_queue_monitoring:message_dropped(),

    chef_wm_actions_queue_monitoring:check_current_state(),

    [{queue_at_capacity,true},
                        {dropped_since_last_check,0},
                        {max_length,99},
                        {last_recorded_length,99},
                        {total_dropped,2}]
        = chef_wm_actions_queue_monitoring:status(),
    meck:unload(ibrowse),
    ok.

