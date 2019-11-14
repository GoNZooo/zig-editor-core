// This probably exists somewhere but I'm not wasting time looking for it
pub fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

