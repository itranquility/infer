(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open! IStd
module F = Format
module L = Logging

(* Tests with exception handling *)

let%expect_test _ =
  let source = {|
try:
      print("TRY BLOCK")
finally:
      print("FINALLY BLOCK")
      |} in
  PyIR.test source ;
  [%expect
    {|
    module dummy:

      toplevel:
        b0:
          n0 <- TOPLEVEL[print]
          n1 <- n0("TRY BLOCK")
          jmp b1

        b1:
          n2 <- TOPLEVEL[print]
          n3 <- n2("FINALLY BLOCK")
          jmp b2

        b2:
          return None |}]


let%expect_test _ =
  let source =
    {|
try:
      print("TRY BLOCK")
finally:
      if foo:
          print("X")
      else:
          print("Y")
      print("FINALLY BLOCK")
print("END")
          |}
  in
  PyIR.test source ;
  [%expect
    {|
    module dummy:

      toplevel:
        b0:
          n0 <- TOPLEVEL[print]
          n1 <- n0("TRY BLOCK")
          jmp b1

        b1:
          n2 <- TOPLEVEL[foo]
          if n2 then jmp b2 else jmp b3

        b2:
          n5 <- TOPLEVEL[print]
          n6 <- n5("X")
          jmp b4

        b3:
          n3 <- TOPLEVEL[print]
          n4 <- n3("Y")
          jmp b4

        b4:
          n7 <- TOPLEVEL[print]
          n8 <- n7("FINALLY BLOCK")
          jmp b5

        b5:
          n9 <- TOPLEVEL[print]
          n10 <- n9("END")
          return None |}]


let%expect_test _ =
  let source =
    {|
try:
  print("TRY BLOCK")
except:
  print("EXCEPT BLOCK")
print("END")
          |}
  in
  PyIR.test source ;
  [%expect
    {|
    module dummy:

      toplevel:
        b0:
          n0 <- TOPLEVEL[print]
          n1 <- n0("TRY BLOCK")
          jmp b3

        b3:
          n2 <- TOPLEVEL[print]
          n3 <- n2("END")
          return None |}]


let%expect_test _ =
  let source =
    {|
import os


try:
    page_size = os.sysconf('SC_PAGESIZE')
except (ValueError, AttributeError):
    try:
        page_size = 0
    except (ValueError, AttributeError):
        page_size = 4096
                 |}
  in
  PyIR.test source ;
  [%expect
    {|
    module dummy:

      toplevel:
        b0:
          n0 <- $ImportName(os)(None, 0)
          TOPLEVEL[os] <- n0
          n1 <- TOPLEVEL[os]
          n2 <- n1.sysconf("SC_PAGESIZE")
          TOPLEVEL[page_size] <- n2
          jmp b8

        b8:
          return None |}]


let%expect_test _ =
  let source =
    {|
import foo

def f(x):
    for i in x:
        e = foo.Foo()
        try:
            print("yolo")
        finally:
            e.bar()
        |}
  in
  PyIR.test source ;
  [%expect
    {|
    module dummy:

      toplevel:
        b0:
          n0 <- $ImportName(foo)(None, 0)
          TOPLEVEL[foo] <- n0
          TOPLEVEL[f] <- $FuncObj(f, dummy.f, {})
          return None


      dummy.f:
        b0:
          n0 <- LOCAL[x]
          n1 <- $GetIter(n0)
          jmp b1

        b1:
          n2 <- $NextIter(n1)
          n3 <- $HasNextIter(n1)
          if n3 then jmp b2 else jmp b5

        b2:
          LOCAL[i] <- n2
          n4 <- GLOBAL[foo]
          n5 <- n4.Foo()
          LOCAL[e] <- n5
          n6 <- GLOBAL[print]
          n7 <- n6("yolo")
          jmp b3

        b3:
          n8 <- LOCAL[e]
          n9 <- n8.bar()
          jmp b4

        b4:
          jmp b1

        b5:
          return None |}]


let%expect_test _ =
  let source =
    {|
from foo import ERROR

with open("foo", "r") as fp:
    for line in fp:
        try:
            print("TRY")
        except ERROR:
            print("EXCEPT")
        else:
            print("ELSE")
        |}
  in
  PyIR.test ~debug:true source ;
  [%expect
    {|
    Translating dummy...
    Building a new node, starting from offset 0
                  []
       2        0 LOAD_CONST                        0 (0)
                  [0]
                2 LOAD_CONST                        1 (("ERROR"))
                  [0; ("ERROR")]
                4 IMPORT_NAME                       0 (foo)
                  [n0]
                6 IMPORT_FROM                       1 (ERROR)
                  [n0; n1]
                8 STORE_NAME                        1 (ERROR)
                  [n0]
               10 POP_TOP                           0
                  []
       4       12 LOAD_NAME                         2 (open)
                  [n2]
               14 LOAD_CONST                        2 ("foo")
                  [n2; "foo"]
               16 LOAD_CONST                        3 ("r")
                  [n2; "foo"; "r"]
               18 CALL_FUNCTION                     2
                  [n3]
               20 SETUP_WITH                       66
                  [CM(n3).__exit__; n4]
               22 STORE_NAME                        3 (fp)
                  [CM(n3).__exit__]
       5       24 LOAD_NAME                         3 (fp)
                  [CM(n3).__exit__; n5]
               26 GET_ITER                          0
                  [CM(n3).__exit__; n6]
    Successors: 28

    Building a new node, starting from offset 28
                  [CM(n3).__exit__; n6]
         >>>   28 FOR_ITER                         54 (to +54)
                  [CM(n3).__exit__; n6; n7]
    Successors: 30,84

    Building a new node, starting from offset 84
                  [CM(n3).__exit__]
         >>>   84 POP_BLOCK                         0
                  [CM(n3).__exit__]
               86 BEGIN_FINALLY                     0
                  [CM(n3).__exit__; None]
    Successors: 88

    Building a new node, starting from offset 88
                  [CM(n3).__exit__; None]
         >>>   88 WITH_CLEANUP_START                0
                  [None; None; n9]
               90 WITH_CLEANUP_FINISH               0
                  [None]
               92 END_FINALLY                       0
                  []
    Successors: 94

    Building a new node, starting from offset 94
                  []
               94 LOAD_CONST                        7 (None)
                  [None]
               96 RETURN_VALUE                      0
                  []
    Successors:

    Building a new node, starting from offset 30
                  [CM(n3).__exit__; n6; n7]
               30 STORE_NAME                        4 (line)
                  [CM(n3).__exit__; n6]
       6       32 SETUP_FINALLY                    12
                  [CM(n3).__exit__; n6]
       7       34 LOAD_NAME                         5 (print)
                  [CM(n3).__exit__; n6; n10]
               36 LOAD_CONST                        4 ("TRY")
                  [CM(n3).__exit__; n6; n10; "TRY"]
               38 CALL_FUNCTION                     1
                  [CM(n3).__exit__; n6; n11]
               40 POP_TOP                           0
                  [CM(n3).__exit__; n6]
               42 POP_BLOCK                         0
                  [CM(n3).__exit__; n6]
               44 JUMP_FORWARD                     28 (to +28)
                  [CM(n3).__exit__; n6]
    Successors: 74

    Building a new node, starting from offset 74
                  [CM(n3).__exit__; n6]
      11 >>>   74 LOAD_NAME                         5 (print)
                  [CM(n3).__exit__; n6; n12]
               76 LOAD_CONST                        6 ("ELSE")
                  [CM(n3).__exit__; n6; n12; "ELSE"]
               78 CALL_FUNCTION                     1
                  [CM(n3).__exit__; n6; n13]
               80 POP_TOP                           0
                  [CM(n3).__exit__; n6]
               82 JUMP_ABSOLUTE                    28 (to 28)
                  [CM(n3).__exit__; n6]
    Successors: 28


    module dummy:

      toplevel:
        b0:
          n0 <- $ImportName(foo)(("ERROR"), 0)
          n1 <- $ImportFrom(ERROR)(n0)
          TOPLEVEL[ERROR] <- n1
          n2 <- TOPLEVEL[open]
          n3 <- n2("foo", "r")
          n4 <- n3.__enter__()
          TOPLEVEL[fp] <- n4
          n5 <- TOPLEVEL[fp]
          n6 <- $GetIter(n5)
          jmp b1

        b1:
          n7 <- $NextIter(n6)
          n8 <- $HasNextIter(n6)
          if n8 then jmp b2 else jmp b7

        b2:
          TOPLEVEL[line] <- n7
          n10 <- TOPLEVEL[print]
          n11 <- n10("TRY")
          jmp b6

        b6:
          n12 <- TOPLEVEL[print]
          n13 <- n12("ELSE")
          jmp b1

        b7:
          jmp b8

        b8:
          n9 <- n3.__enter__(None, None, None)
          jmp b9

        b9:
          return None |}]


let%expect_test _ =
  let source =
    {|
TICKS=0

def subhelper():
    global TICKS
    TICKS += 2
    for i in range(2):
        try:
            print("foo")
        except AttributeError:
            TICKS += 3
        |}
  in
  PyIR.test source ;
  [%expect
    {|
    module dummy:

      toplevel:
        b0:
          GLOBAL[TICKS] <- 0
          TOPLEVEL[subhelper] <- $FuncObj(subhelper, dummy.subhelper, {})
          return None


      dummy.subhelper:
        b0:
          n0 <- GLOBAL[TICKS]
          n1 <- $Inplace.Add(n0, 2)
          GLOBAL[TICKS] <- n1
          n2 <- GLOBAL[range]
          n3 <- n2(2)
          n4 <- $GetIter(n3)
          jmp b1

        b1:
          n5 <- $NextIter(n4)
          n6 <- $HasNextIter(n4)
          if n6 then jmp b2 else jmp b7

        b2:
          LOCAL[i] <- n5
          n7 <- GLOBAL[print]
          n8 <- n7("foo")
          jmp b1

        b7:
          return None |}]


let%expect_test _ =
  let source =
    {|
def foo():
          pass

try:
          foo()
except C as c:
          print(c)
          |}
  in
  PyIR.test source ;
  [%expect
    {|
    module dummy:

      toplevel:
        b0:
          TOPLEVEL[foo] <- $FuncObj(foo, dummy.foo, {})
          n0 <- TOPLEVEL[foo]
          n1 <- n0()
          jmp b6

        b6:
          return None


      dummy.foo:
        b0:
          return None |}]


let%expect_test _ =
  let source =
    {|
async def async_with(filename):
    async with open(filename, 'r') as f:
        await f.read()
|}
  in
  PyIR.test source ;
  [%expect
    {|
    module dummy:

      toplevel:
        b0:
          TOPLEVEL[async_with] <- $FuncObj(async_with, dummy.async_with, {})
          return None


      dummy.async_with:
        b0:
          n0 <- GLOBAL[open]
          n1 <- LOCAL[filename]
          n2 <- n0(n1, "r")
          n3 <- n2.__enter__()
          n4 <- $GetAwaitable(n3)
          n5 <- $YieldFrom(n4, None)
          LOCAL[f] <- n4
          n6 <- LOCAL[f]
          n7 <- n6.read()
          n8 <- $GetAwaitable(n7)
          n9 <- $YieldFrom(n8, None)
          jmp b1

        b1:
          n10 <- n2.__enter__(None, None, None)
          n11 <- $GetAwaitable(n10)
          n12 <- $YieldFrom(n11, None)
          jmp b2

        b2:
          return None |}]


let%expect_test _ =
  let source =
    {|
def call_finally():
    try:
        read()
    except Exception as e:
        return
|}
  in
  PyIR.test source ;
  [%expect
    {|
    module dummy:

      toplevel:
        b0:
          TOPLEVEL[call_finally] <- $FuncObj(call_finally, dummy.call_finally, {})
          return None


      dummy.call_finally:
        b0:
          n0 <- GLOBAL[read]
          n1 <- n0()
          jmp b7

        b7:
          return None |}]


let%expect_test _ =
  let source =
    {|
def call_finally_with_break():
    for i in range(100):
        try:
            read()
        except Exception as e:
            break
|}
  in
  PyIR.test source ;
  [%expect
    {|
    module dummy:

      toplevel:
        b0:
          TOPLEVEL[call_finally_with_break] <- $FuncObj(call_finally_with_break, dummy.call_finally_with_break, {})
          return None


      dummy.call_finally_with_break:
        b0:
          n0 <- GLOBAL[range]
          n1 <- n0(100)
          n2 <- $GetIter(n1)
          jmp b1

        b1:
          n3 <- $NextIter(n2)
          n4 <- $HasNextIter(n2)
          if n4 then jmp b2 else jmp b11

        b11:
          return None

        b2:
          LOCAL[i] <- n3
          n5 <- GLOBAL[read]
          n6 <- n5()
          jmp b1 |}]


let%expect_test _ =
  let source = {|
def raise_from(e):
    raise IndexError from e
|} in
  PyIR.test source ;
  [%expect
    {|
    module dummy:

      toplevel:
        b0:
          TOPLEVEL[raise_from] <- $FuncObj(raise_from, dummy.raise_from, {})
          return None


      dummy.raise_from:
        b0:
          n0 <- GLOBAL[IndexError]
          n1 <- LOCAL[e]
          n0.__cause__ <- n1
          throw n0 |}]


let%expect_test _ =
  let source =
    {|
async def foo():
    async with read1(), read2():
        with read3():
            await action()
|}
  in
  PyIR.test source ;
  [%expect
    {|
    module dummy:

      toplevel:
        b0:
          TOPLEVEL[foo] <- $FuncObj(foo, dummy.foo, {})
          return None


      dummy.foo:
        b0:
          n0 <- GLOBAL[read1]
          n1 <- n0()
          n2 <- n1.__enter__()
          n3 <- $GetAwaitable(n2)
          n4 <- $YieldFrom(n3, None)
          n5 <- GLOBAL[read2]
          n6 <- n5()
          n7 <- n6.__enter__()
          n8 <- $GetAwaitable(n7)
          n9 <- $YieldFrom(n8, None)
          n10 <- GLOBAL[read3]
          n11 <- n10()
          n12 <- n11.__enter__()
          n13 <- GLOBAL[action]
          n14 <- n13()
          n15 <- $GetAwaitable(n14)
          n16 <- $YieldFrom(n15, None)
          jmp b1

        b1:
          n17 <- n11.__enter__(None, None, None)
          jmp b2

        b2:
          jmp b3

        b3:
          n18 <- n6.__enter__(None, None, None)
          n19 <- $GetAwaitable(n18)
          n20 <- $YieldFrom(n19, None)
          jmp b4

        b4:
          jmp b5

        b5:
          n21 <- n1.__enter__(None, None, None)
          n22 <- $GetAwaitable(n21)
          n23 <- $YieldFrom(n22, None)
          jmp b6

        b6:
          return None |}]


let%expect_test _ =
  let source =
    {|
async def foo():
    with read1():
        try:
            with read2():
                res = await get()
            return res
        finally:
            do_finally()
|}
  in
  PyIR.test_cfg_skeleton source ;
  PyIR.test source ;
  [%expect
    {|
    dummy
       2        0 LOAD_CONST                        0 (<code object foo>)
                2 LOAD_CONST                        1 ("foo")
                4 MAKE_FUNCTION                     0
                6 STORE_NAME                        0 (foo)
                8 LOAD_CONST                        2 (None)
               10 RETURN_VALUE                      0
    CFG successors:
       0:
    CFG predecessors:
       0:
    topological order: 0

    dummy.foo
       3        0 LOAD_GLOBAL                       0 (read1)
                2 CALL_FUNCTION                     0
                4 SETUP_WITH                       66
                6 POP_TOP                           0
       4        8 SETUP_FINALLY                    50
       5       10 LOAD_GLOBAL                       2 (read2)
               12 CALL_FUNCTION                     0
               14 SETUP_WITH                       18
               16 POP_TOP                           0
       6       18 LOAD_GLOBAL                       3 (get)
               20 CALL_FUNCTION                     0
               22 GET_AWAITABLE                     0
               24 LOAD_CONST                        0 (None)
               26 YIELD_FROM                        0
               28 STORE_FAST                        0 (res)
               30 POP_BLOCK                         0
               32 BEGIN_FINALLY                     0
         >>>   34 WITH_CLEANUP_START                0
               36 WITH_CLEANUP_FINISH               0
               38 END_FINALLY                       0
       7       40 LOAD_FAST                         0 (res)
               42 POP_BLOCK                         0
               44 CALL_FINALLY                     14
               46 POP_BLOCK                         0
               48 ROT_TWO                           0
               50 BEGIN_FINALLY                     0
               52 WITH_CLEANUP_START                0
               54 WITH_CLEANUP_FINISH               0
               56 POP_FINALLY                       0
               58 RETURN_VALUE                      0
       9 >>>   60 LOAD_GLOBAL                       1 (do_finally)
               62 CALL_FUNCTION                     0
               64 POP_TOP                           0
               66 END_FINALLY                       0
               68 POP_BLOCK                         0
               70 BEGIN_FINALLY                     0
         >>>   72 WITH_CLEANUP_START                0
               74 WITH_CLEANUP_FINISH               0
               76 END_FINALLY                       0
               78 LOAD_CONST                        0 (None)
               80 RETURN_VALUE                      0
    CFG successors:
       0: 34
      34: 40
      40: 60
      46: 52
      52:
      60: 46
      68: 72
      72: 78
      78:
    CFG predecessors:
       0:
      34: 0
      40: 34
      46: 60
      52: 46
      60: 40
      68:
      72:
      78:
    topological order: 0 34 40 60 46 52

    module dummy:

      toplevel:
        b0:
          TOPLEVEL[foo] <- $FuncObj(foo, dummy.foo, {})
          return None


      dummy.foo:
        b0:
          n0 <- GLOBAL[read1]
          n1 <- n0()
          n2 <- n1.__enter__()
          n3 <- GLOBAL[read2]
          n4 <- n3()
          n5 <- n4.__enter__()
          n6 <- GLOBAL[get]
          n7 <- n6()
          n8 <- $GetAwaitable(n7)
          n9 <- $YieldFrom(n8, None)
          LOCAL[res] <- n8
          jmp b1

        b1:
          n10 <- n4.__enter__(None, None, None)
          jmp b2

        b2:
          n11 <- LOCAL[res]
          jmp b5

        b3:
          jmp b4

        b4:
          n14 <- n1.__enter__(None, None, None)
          return n11

        b5:
          n12 <- GLOBAL[do_finally]
          n13 <- n12()
          jmp b3 |}]


let%expect_test _ =
  let source =
    {|
def foo():
    num_attempts = 25
    while num_attempts > 0:
        try:
            should_stop, output = stop_conditionx()
            if should_stop:
                return output
        except Exception:
            if retry_on_failure and num_attempts > 1:
                continue
            else:
                raise
        finally:
            num_attempts = num_attempts - 1
    return
|}
  in
  PyIR.test source ;
  [%expect {|
    IR error: Cannot pop, stack is empty |}]
