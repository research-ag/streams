module {
  public func create(maxLength : Nat) : (() -> { accept : (item : Text) -> ??Text }) {
    class counter() {
      var sum = 0;
      // Any individual item larger than maxLength is wrapped to null
      // and its size is not counted.
      func wrap(item : Text) : (?Text, Nat) {
        let s = item.size();
        if (s <= maxLength) (?item, s) else (null, 0);
      };
      public func accept(item : Text) : ??Text {
        let (wrapped, size) = wrap(item);
        sum += size;
        if (sum <= maxLength) ?wrapped else null;
      };
    };
    counter;
  };
};
