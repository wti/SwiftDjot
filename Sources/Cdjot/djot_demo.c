#include "djot_demo.h"

/* return 0 if able to parse and print to html. */
int djot_demo() {
  lua_State *me = djot_open();
  if (me == NULL) {
    return 1;
  }
  char* input = "# hi";
  int parseResult = djot_parse(me, input, false);
  if (1 != parseResult) { // 1 is success, 0 error (weirdly)
    djot_close(me);
    return 100 + parseResult;
  }
  char* html = djot_render_html(me);
  if (NULL == html) {
    djot_close(me);
    return 2;
  }
  printf("## djot_demo result: %s\n", html);
  djot_close(me);
  return 0;
}
