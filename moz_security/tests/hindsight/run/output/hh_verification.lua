-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validates the moz_telemetry_heavy_hitters_monitor output
--]]

require "string"

local result =[[77	0921
41	0741
49	0781
81	0941
89	0981
39	0731
7	0571
79	0931
47	0771
87	0971
33	0701
107	1071
73	0901
109	1081
93	1001
25	0661
111	1091
103	1051
55	0811
105	1061
15	0611
63	0851
23	0651
9	0581
71	0891
61	0841
57	0821
99	1031
29	0681
69	0881
97	1021
21	0641
37	0721
59	0831
27	0671
101	1041
85	0961
67	0871
19	0631
95	1011
65	0861
75	0911
45	0761
5	0561
31	0691
53	0801
17	0621
83	0951
51	0791
43	0751
11	0591
35	0711
3	0551
91	0991
13	0601
]]


local cnt = 0
function process_message()
    local payload = read_message("Payload")
    assert(result == payload, payload)
    cnt = 1
    return 0
end


function timer_event()
    assert(cnt == 1, string.format("%d out of 1 tests ran", cnt))
end
