# Lua Circular Buffer Module

## Overview
A circular buffer library for an in-memory sliding window time series data
store.

## Module

### Example Usage
```lua
require "circular_buffer"

local cb = circular_buffer.new(1440, 1, 60)
local ERRORS = cb:set_header(1, "Errors")
cb:add(1e9, ERRORS, 1)
cb:add(1e9, ERRORS, 7)
local val = cb:get(1e9, ERRORS)
-- val == 8
```
### Functions

#### new
```lua
require "circular_buffer"
local cb = circular_buffer.new(1440, 1, 60)
```

Import the Lua _circular_buffer_ via the Lua 'require' function. The module is
globally registered and returned by the require function.

*Arguments*
- rows (unsigned) The number of rows in the buffer (must be > 1)
- columns (unsigned) The number of columns in the buffer
  (must be > 0 and <= 256)
- seconds_per_row (unsigned) The number of seconds each row represents
  (must be > 0).

*Return*
- circular_buffer userdata object.

#### version
```lua
local v = circular_buffer.version()
-- v == "1.0.0"
```

Returns a string with the running version of circular_buffer.

*Arguments*
- none

*Return*
- Semantic version string

### Methods
**Note:** All column arguments are 1 based. If the column is out of range for
the configured circular buffer a fatal error is generated.

#### add
```lua
d = cb:add(1e9, 1, 1)
-- d == 1
d = cb:add(1e9, 1, 99)
-- d == 100
```

Adds a value to the specified row/column in the circular buffer.

*Arguments*
- nanosecond (unsigned) The number of nanosecond since the UNIX epoch. The value
  is used to determine which row is being operated on.
- column (unsigned) The column within the specified row to perform an add
  operation on.
- value (double) The value to be added to the specified row/column.

*Return*
- The value of the updated row/column or nil if the time was outside the range
  of the buffer.

#### set
```lua
d = cb:set(1e9, 1, 1)
-- d == 1
d = cb:set(1e9, 1, 99)
-- d == 99
```

Overwrites the value at a specific row/column in the circular buffer.

*Arguments*
- nanosecond (unsigned) The number of nanosecond since the UNIX epoch. The value
  is used to determine which row is being operated on.
- column (unsigned) The column within the specified row to perform a set
  operation on.
- value (double) The value to be overwritten at the specified row/column.
  For aggregation methods "min" and "max" the value is only overwritten if it is
  smaller/larger than the current value.

*Return*
- The resulting value of the row/column or nil if the time was outside the range
  of the buffer.

#### get
```lua
d = cb:get(1e9, 1)
-- d == 99
```

Fetches the value at a specific row/column in the circular buffer.

*Arguments*
- nanosecond (unsigned) The number of nanosecond since the UNIX epoch. The value
  is used to determine which row is being operated on.
- column (unsigned) The column within the specified row to retrieve the data
  from.

*Return*
- The value at the specifed row/column or nil if the time was outside the range
  of the buffer.

#### get_delta
```lua
d = cb:get_delta(1e9, 1)
-- d == 99
```

Fetches the delta value at a specific row/column in the circular buffer since
the last reset/output.

*Arguments*
- nanosecond (unsigned) The number of nanosecond since the UNIX epoch. The value
  is used to determine which row is being operated on.
- column (unsigned) The column within the specified row to retrieve the data
  from.

*Return*
- The delta value at the specifed row/column or nil if the time was outside the
  range of the buffer.

#### get_range
```lua
local stats = circular_buffer.new(5, 1, 1)
stats:set(1e9, 1, 1)
stats:set(2e9, 1, 2)
stats:set(3e9, 1, 3)
stats:set(4e9, 1, 4)
stats:set(5e9, 1, 5)

local a = stats:get_range(1, 3e9, 4e9)
-- a = {3, 4}
```

Returns an array of column values spanning the specificed time range.

*Arguments*
- column (unsigned) The column that the computation is performed against.
- start (unsigned _optional_) The number of nanosecond since the UNIX epoch.
  Sets the start time of the computation range; if nil the buffer's start time
  is used.
- end (unsigned _optional_) The number of nanosecond since the UNIX epoch. Sets
  the end time of the computation range (inclusive); if nil the buffer's end
  time is used. The end time must be greater than or equal to the start time.

*Returns*
- Array of column values or nil if the range fell entirely outside of the
  buffer.

#### get_range_delta
```lua
local stats = circular_buffer.new(5, 1, 1)
stats:set(1e9, 1, 1)
stats:set(2e9, 1, 2)
stats:set(3e9, 1, 3)
stats:set(4e9, 1, 4)
stats:set(5e9, 1, 5)

local a = stats:get_range(1, 3e9, 4e9)
-- a = {3, 4}
```

Returns an array of column delta values spanning the specificed time range since
the last reset/output.

*Arguments*
- column (unsigned) The column that the computation is performed against.
- start (unsigned _optional_) The number of nanosecond since the UNIX epoch.
  Sets the start time of the computation range; if nil the buffer's start time
  is used. 
- end (unsigned _optional_) The number of nanosecond since the UNIX epoch. Sets
  the end time of the computation range (inclusive); if nil the buffer's end
  time is used. The end time must be greater than or equal to the start time.

*Returns*
- Array of column delta values or nil if the range fell entirely outside of the
  buffer.

#### get_configuration
```lua
rows, columns, seconds_per_row = cb:get_configuration()
-- rows == 1440
-- columns = 1
-- seconds_per_row = 60
```

Returns the configuration options passed to _new_.

*Arguments*
- none

*Return*
- The circular buffer dimension values specified in the constructor.
    - rows
    - columns
    - seconds_per_row

#### current_time
```lua
t = cb:current_time()
-- t == 86340000000000

```

Returns the timestamp of the newest row.

*Arguments*
- none

*Return*
- The time of the most current row in the circular buffer (nanoseconds).

#### set_header
```lua
column = cb:set_header(1, "Errors")
-- column == 1

```

Sets the header metadata for the specifed column.

*Arguments*
- column (unsigned) The column number where the header information is applied.
- name (string) Descriptive name of the column (maximum 15 characters). Any non
  alpha numeric characters will be converted to underscores. (default: Column_N)
- unit (string _optional_) The unit of measure (maximum 7 characters). Alph
  numeric, '/', and '*' characters are allowed everything else will be converted
  to underscores. i.e. KiB, Hz, m/s (default: count)
- aggregation_method (string _optional_) Controls how the column data is
  aggregated when combining multiple circular buffers.
    - **sum** The total is computed for the time/column (default).
    - **min** The smallest value is retained for the time/column.
    - **max** The largest value is retained for the time/column.
    - **none** No aggregation will be performed the column.

*Return*
- The column number passed into the function.

#### get_header
```lua
name, unit, aggregation_method = cb:get_header(1)
-- name == "Errors"
-- unit == "count"
-- aggregation_method == "sum"

```

Retrieves the header metadata for the specified column.

*Arguments*
- column (unsigned) The column number of the header information to be retrieved.

*Return*
- The current values of specified header column.
    - name
    - unit
    - aggregation_method

#### reset_delta
```lua
-- only available when using the non lua_sandbox (the sandbox output manages the
-- reset in that case)
cb:reset_delta(")

```

Resets the delta counts back to initialized.

*Arguments*
- none

*Return*
- none

#### annotate
```lua
-- only available when using the lua_sandbox
cb:annotate(1e9, 1, "alert", "Anonmaly detected rate of change exceeded 2 standard deviations")
```

Creates/Overwrites the annotation at a specific row/column in the circular
buffer.

*Arguments*
- nanosecond (unsigned) The number of nanosecond since the UNIX epoch. The value
  is used to determine which row is being operated on.
- column (unsigned) The column within the specified row to perform a set
  operation on.
- type (string) - info|alert
- annotation (string) - full text of the annotation
- delta (bool _optional_) - include the change in the cbufd ouput (default true)

*Return*
- none

#### format
```lua
-- only available when using the lua_sandbox
cb:format("cbufd")

```

Sets an internal flag to control the output format of the circular buffer data
structure.

*Arguments*
- format (string)
    - **cbuf** The circular buffer full data set format.
    - **cbufd** The circular buffer delta data set format.

*Return*
- The circular buffer object.

### Output
```lua
-- only available when using the lua_sandbox todo: add tostring support
cb:format("cbuf")
output(cb) -- serializes the full buffer
cb:format("cbufd")
output(cb) -- serializes the delta of the buffer since the last output

```

The circular buffer can be passed to the lua_sandbox output() function. The
output format can be selected using the format() function.

The cbuf (full data set) output format consists of newline delimited rows
starting with a json header row followed by the data rows with tab delimited
columns. The time in the header corresponds to the time of the first data row,
the time for the other rows is calculated using the seconds_per_row header
value.

    {json header}
    row1_col1\trow1_col2\n
    .
    .
    .
    rowN_col1\trowN_col2\n

The cbufd (delta) output format consists of newline delimited rows starting with
a json header row followed by the data rows with tab delimited columns. The
first column is the timestamp for the row (time_t). The cbufd output will only
contain the rows that have changed and the corresponding delta values for each
column.

    {json header}
    row14_timestamp\trow14_col1\trow14_col2\n
    row10_timestamp\trow10_col1\trow10_col2\n

Sample Cbuf Output
------------------

    {"time":2,"rows":3,"columns":3,"seconds_per_row":60,"column_info":[{"name":"HTTP_200","unit":"count","aggregation":"sum"},{"name":"HTTP_400","unit":"count","aggregation":"sum"},{"name":"HTTP_500","unit":"count","aggregation":"sum"}], "annotations":[]}
    10002   0   0
    11323   0   0
    10685   0   0
