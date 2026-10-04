# duplicate Drive names error instead of picking one

    Code
      rec$adapter$exists("a.csv")
    Condition
      Error in `.resolve_real_path()`:
      ! 2 Drive items are named "a.csv" at 'a.csv'.
      i gdpins cannot tell which one to use. Keep one and trash the others:
      * id id_1, modified 2024-01-01T00:00:00.000Z
      * id id_2, modified 2024-02-01T00:00:00.000Z

