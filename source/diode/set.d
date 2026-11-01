/// A basic implementation of a set: a data structure which holds a collection of unique objects.
/// No object can be inserted twice, unless it is removed from the set.
module diode.set;

@safe:

import std.range;
import std.algorithm;
import diode.object;

/// Implementation of a set. Each struct inside of a set may only appear once.
///
/// `Set` currently uses a plain, unsorted array to manage its data. This might change in the
/// future. The order may change as items are added or removed from the set.
struct Set(T) {

    private {
        Appender!(T[]) _data;
    }

    this(T[] data) {
        this._data = data;
    }

    /// Returns:
    ///     True if the set is empty (has no elements in it).
    bool isEmpty() const {
        return length == 0;
    }

    /// Returns:
    ///     length = Number of items in the set.
    size_t length() const {
        return _data[].length;
    }

    /// Returns:
    ///     A shallow copy of the set.
    Set!T dup() {
        return Set!T(_data[].dup);
    }

    /// Insert an item into the set.
    /// Params:
    ///     key = Key to insert.
    /// Returns:
    ///     True if the item was inserted.
    bool add(T key) {
        if (key !in this) {
            _data ~= key;
            return true;
        }
        return false;
    }

    /// Insert a range of items into the set.
    /// Params:
    ///     range = A range that yields a number of elements that can be added to the set.
    void add(Range)(Range range)
    if (isInputRange!Range) {
        foreach (item; range) {
            add(item);
        }
    }

    /// Insert a given item into the set if it casts into the type accepted by the set.
    ///
    /// In other words, this function performs a dynamic cast into type `T`. If the cast fails,
    /// the item will not be inserted.
    ///
    /// Params:
    ///     key = Item to insert.
    /// Returns:
    ///     True if the item was inserted.
    bool addIfCasts(X)(X key) {
        if (auto validKey = cast(T) key) {
            return add(validKey);
        }
        return false;
    }

    /// Add an element to the set, or remove it if it exists.
    /// Returns:
    ///     True, if the key was added, false if removed.
    bool toggle(T key) {
        if (key in this) {
            remove(key);
            return false;
        }
        else {
            _data ~= key;
            return true;
        }
    }

    /// Remove an item from the set. Does nothing if the item doesn't exist in the set.
    /// Params:
    ///     key = Item to remove.
    /// Returns:
    ///     True if the item was removed.
    bool remove(const T key) {
        auto shortened = _data[].remove!(a => equals(a, key));
        auto wasRemoved = _data[].length != shortened.length;
        _data.shrinkTo(shortened.length);
        return wasRemoved;
    }

    /// Remove a range of items from the set.
    /// Params:
    ///     range = A range of items to remove. Each of the items will be removed.
    ///         Items that don't exist in the set are ignored.
    void remove(Range)(Range range)
    if (isInputRange!Range) {
        foreach (item; range) {
            remove(item);
        }
    }

    /// Remove an item from the set but only if it can be casted into `const T` first.
    /// Params:
    ///     key = Item to remove from the set.
    void removeIfCasts(X)(const X key) {
        if (auto validKey = cast(const T) key) {
            remove(validKey);
        }
    }

    /// Remove all data from the set.
    void clear() {
        _data.clear();
    }

    /// Check if the given item can be found in the set.
    /// Params:
    ///     key = Item to find in the set.
    /// Returns:
    ///     True if the item exists in the set.
    bool opBinaryRight(string op : "in")(const T key) const {
        return _data[].canFind!((const T a, const T b) => equals(a, b))(key);
    }

    /// Insert an item into the set.
    /// Params:
    ///     key = Key to insert into the set.
    void opOpAssign(string op : "~")(T key) {
        add(key);
    }

    /// Insert a range of items into the set.
    /// Params:
    ///     range = A range that yields items to be inserted into the set.
    void opOpAssign(string op : "~", Range)(Range range)
    if (isInputRange!Range) {
        foreach (key; range) {
            add(key);
        }
    }

    /// Convert the set into an array.
    /// Returns:
    ///     An array containing data of the set.
    inout(T)[] array() inout {
        return _data[];
    }

    /// Get a range that accesses the set.
    alias opIndex = array;

}

@("Set works for integral types")
unittest {
    Set!int numbers;
    numbers ~= 1;
    numbers ~= 2;
    numbers ~= 3;
    assert(0 !in numbers);
    assert(1  in numbers);
    assert(2  in numbers);
    assert(3  in numbers);
    assert(4 !in numbers);
}

@("Set works with indirections")
unittest {
    class Foo : Safe {
        mixin implementSafe;
    }
    Set!Foo set;
    auto a = new Foo;
    auto b = new Foo;
    auto c = new Foo;
    set.add(a);
    set.add(b);
    set.remove(a);
    assert(a !in set);
    assert(b  in set);
    assert(c !in set);
}
