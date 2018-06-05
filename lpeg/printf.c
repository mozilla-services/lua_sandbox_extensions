#include <stdio.h>

// gcc --std=c99 printf.c
int main(int argc, char* argv[])
{
  int i = 123;
  int ni = -123;
  char s[] = "sample";
  char c = 'c';
  double d = 12.3456789;

  printf("`%i`\n", i);
  printf("`%d`\n", i);
  printf("`%d`\n", ni);
  printf("`%+d`\n", i);
  printf("`% d`\n", i);
  printf("`%5d`\n", i);
  printf("`%05d`\n", i);
  printf("`%+5d`\n", i);
  printf("`%-+6d`\n", i);
  printf("`%c`\n", c);
  printf("`%2c`\n", c);
  printf("`%s`\n", s);
  printf("`%10s`\n", s);
  printf("`%-10s`\n", s);
  printf("`%*s`\n", 10, s);
  printf("`%-*s`\n", 10, s);
  printf("`%o`\n", i);
  printf("`%#o`\n", i);
  printf("`%x`\n", i);
  printf("`%#x`\n", i);
  printf("`%X`\n", i);
  printf("`%f`\n", d);
  printf("`%F`\n", d);
  printf("`%e`\n", d);
  printf("`%E`\n", d);
  printf("`%g`\n", d);
  printf("`%G`\n", d);
  printf("`%a`\n", d);
  printf("`%A`\n", d);
  printf("`%p`\n", s);
  printf("'This %s test'\n", "is a space");
  printf("'%5s%5s%5s'\n", "c1", "c2", "c3");
  printf("'%-5s%-5s%-5s'\n", "c1", "c2", "c3");
  printf("'Everything %d %c %g %s'\n", i, c, d, s);
  printf("'Everything together %d%c%g%s'\n", i, c, d, s);
  printf("'Multi string '%s' '%s''\n", "1 2'3", "4 5 6");
  printf("'Dquote string \"%s\"'\n", "foo bar");
  printf("'%-5s %-6s %-7s'\n", "c", "c1", "c11");
  printf("'%.3s%.3s'\n", "A\0A", "BBB");
  printf("'%-3.3s%.3s'\n", "A\0A", "BBB");
}


