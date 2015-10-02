%% Copyright 2015 Opscode, Inc. All Rights Reserved.
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

-module(chef_wm_actions_queue_monitoring_tests).

-include_lib("eunit/include/eunit.hrl").

max_length_test() ->
    MaxLengthJson = "{\"vhost\":\"/analytics\",\"name\":\"max_length\",\"pattern\":\"(erchef|alaska|notifier.notifications|notifier_config)\",\"apply-to\":\"queues\",\"definition\":{\"max-length\":10},\"priority\":0}",
    Result = chef_wm_actions_queue_monitoring:parse_max_length_response(MaxLengthJson),
    ?assertEqual(10, Result).

max_length_invalid_json_test() ->
    MaxLengthJson = "{abc",
    Result = chef_wm_actions_queue_monitoring:parse_max_length_response(MaxLengthJson),
    ?assertEqual(undefined, Result).


current_length_no_queue_test() ->
    NoQueueJson = "[]",
    Result = chef_wm_actions_queue_monitoring:parse_current_length_response(NoQueueJson),
    ?assertEqual(undefined, Result).


current_length_no_messages_test() ->
    Json = "[{\"memory\":10160,\"messages\":0,\"messages_details\":{\"rate\":0.0},\"messages_ready\":0,\"messages_ready_details\":{\"rate\":0.0},\"messages_unacknowledged\":0,\"messages_unacknowledged_details\":{\"rate\":0.0},\"idle_since\":\"2015-10-02 11:23:28\",\"consumer_utilisation\":\"\",\"policy\":\"max_length\",\"exclusive_consumer_tag\":\"\",\"consumers\":0,\"backing_queue_status\":{\"q1\":0,\"q2\":0,\"delta\":[\"delta\",\"undefined\",0,\"undefined\"],\"q3\":0,\"q4\":0,\"len\":0,\"pending_acks\":0,\"target_ram_count\":\"infinity\",\"ram_msg_count\":0,\"ram_ack_count\":0,\"next_seq_id\":0,\"persistent_count\":0,\"avg_ingress_rate\":0.0,\"avg_egress_rate\":0.0,\"avg_ack_ingress_rate\":0.0,\"avg_ack_egress_rate\":0.0},\"state\":\"running\",\"name\":\"alaska\",\"vhost\":\"/analytics\",\"durable\":true,\"auto_delete\":false,\"arguments\":{},\"node\":\"rabbit@localhost\"}]",
    Result = chef_wm_actions_queue_monitoring:parse_current_length_response(Json),
    ?assertEqual(0, Result).


current_length_invalid_json_test() ->
    Json = "{abc",
    Result = chef_wm_actions_queue_monitoring:parse_current_length_response(Json),
    ?assertEqual(undefined, Result).


current_length_some_messages_test() ->
    Json = "[{\"memory\":14696,\"message_stats\":{\"publish\":7,\"publish_details\":{\"rate\":0.0}},\"messages\":7,\"messages_details\":{\"rate\":0.2},\"messages_ready\":7,\"messages_ready_details\":{\"rate\":0.2},\"messages_unacknowledged\":0,\"messages_unacknowledged_details\":{\"rate\":0.0},\"idle_since\":\"2015-10-02 11:25:03\",\"consumer_utilisation\":\"\",\"policy\":\"max_length\",\"exclusive_consumer_tag\":\"\",\"consumers\":0,\"backing_queue_status\":{\"q1\":0,\"q2\":0,\"delta\":[\"delta\",\"undefined\",0,\"undefined\"],\"q3\":0,\"q4\":7,\"len\":7,\"pending_acks\":0,\"target_ram_count\":\"infinity\",\"ram_msg_count\":7,\"ram_ack_count\":0,\"next_seq_id\":7,\"persistent_count\":0,\"avg_ingress_rate\":0.5989904375605838,\"avg_egress_rate\":0.0,\"avg_ack_ingress_rate\":0.0,\"avg_ack_egress_rate\":0.0},\"state\":\"running\",\"name\":\"alaska\",\"vhost\":\"/analytics\",\"durable\":true,\"auto_delete\":false,\"arguments\":{},\"node\":\"rabbit@localhost\"}]",
    Result = chef_wm_actions_queue_monitoring:parse_current_length_response(Json),
    ?assertEqual(7, Result).

