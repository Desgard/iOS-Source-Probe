var x1 >= 0;
var x2 >= 0;

minimize obj: x1 + 2 * x2;

c1: x1 + x2 <= 2;
c2: x1 + x2 >= 1;

solve;
display x1;
display x2;
end;
