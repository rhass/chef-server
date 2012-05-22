%% @copyright 2012 Opscode, Inc. All Rights Reserved
%% @author Tim Dysinger <dysinger@opscode.com>
%%
%% Licensed to the Apache Software Foundation (ASF) under one or more
%% contributor license agreements.  See the NOTICE file distributed
%% with this work for additional information regarding copyright
%% ownership.  The ASF licenses this file to you under the Apache
%% License, Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain a copy of
%% the License at http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
%% implied.  See the License for the specific language governing
%% permissions and limitations under the License.
-module(bksw_req).

-export([with_amz_request_id/1, with_etag/2]).

-include_lib("cowboy/include/http.hrl").

%%===================================================================
%% API functions
%%===================================================================
with_amz_request_id(Rq) ->
    Id = term_to_binary({node(), erlang:now()}),
    Base64 = bksw_format:to_base64(Id),
    {ok, Rq2} =
        cowboy_http_req:set_resp_header(<<"x-amz-request-id">>,
                                        Base64, Rq),
    Rq2.

with_etag(Etag, Rq) ->
    {ok, Rq2} = cowboy_http_req:set_resp_header('Etag',
                                                Etag, Rq),
    Rq2.