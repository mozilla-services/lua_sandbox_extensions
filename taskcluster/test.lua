s = "foo\t\t\tbar\ttest"
for str in string.gmatch(s, "([^\t]*)") do
 print(".", str)
end
