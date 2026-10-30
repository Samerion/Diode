/// Interfaces for `@safe` objects.
module diode.object;

@safe:

/// Base interface for safe objects.
interface Safe {

    /// Compare two objects for equality.
    bool opEquals(const Object) const;

    /// Safe object-to-string conversion.
    /// Returns:
    ///     Representation of the object as a string.
    string toString() const;

}

@("Safe objects can be compared in safe code")
unittest {
    class A : Safe {
        override bool opEquals(const Object other) const {
            return this is other;
        }

        override string toString() const {
            return typeid(this).toString();
        }
    }

    auto a = new A;
    assert(new A != new A);
    assert(new A != a);
    assert(a == a);
}

/// Compare two objects or interface instances in a safe manner.
///
/// The D runtime will fail to infer equality comparison using the `==` operator as `@safe`
/// if the argument on either side is an instance of an interface. To illustrate, this
/// hypothetical example would fail to compile:
///
/// ---
/// interface Interface { }
///
/// bool test(Object left, Interface right) @safe {
///     return left == right;  // inferred @system
/// }
/// ---
///
/// The `equals` function , given that the left side of the comparison implements the [Safe]
/// interface, can correctly compare objects in `@safe` contexts.
///
/// This function abandons the D runtime paradigm of supporting `T.opEquals(T)` for arbitrary
/// object types; therefore, there is no `Safe.opEquals(Safe)` overload. The `opEquals(const
/// Object)` overload is the only overload used. The reasoning behind this decision is that
/// mixing different `opEquals` overloads does not play well with D's method shadowing logic.
///
/// Params:
///     left  = Left side of the comparison.
///     right = Right side of the comparison.
/// Returns:
///     True if the objects are equal.
bool equals(const Safe left, const Object right) {
    if (left is null || right is null) {
        return left is null
            && right is null;
    }
    return left.opEquals(right);
}

/// Implementation for `equals` for non-object types. Performs comparison using the `==` operator.
///
/// This overload allows safe struct and object comparison in a generic (templated) context.
///
/// Params:
///     left  = Left side of the comparison.
///     right = Right side of the comparison.
/// Returns:
///     True if the two objects are equal.
bool equals(A, B)(A left, B right)
if (!is(A : const Safe) || !is(B : const Object)){
    return left == right;
}

@("equals can compare interfaces in @safe code")
unittest {
    class A : Safe {
        int value;

        this(int value) {
            this.value = value;
        }

        override bool opEquals(const Object other) const {
            if (auto a = cast(const A) other) {
                return value == a.value;
            }
            else {
                return false;
            }
        }

        override string toString() const {
            return typeid(this).toString();
        }
    }

    auto a1 = new A(1);
    auto a2 = new A(2);
    auto safe1 = a1;
    auto safe2 = a2;

    assert( equals(a1, a1));
    assert( equals(a2, a2));
    assert(!equals(a1, a2));
    assert(!equals(a2, a1));

    assert( equals(a1, safe1));
    assert( equals(a2, safe2));
    assert(!equals(a1, safe2));
    assert(!equals(a2, safe1));

    assert( equals(safe1, a1));
    assert( equals(safe2, a2));
    assert(!equals(safe1, a2));
    assert(!equals(safe2, a1));

    assert( equals(safe1, safe1));
    assert( equals(safe2, safe2));
    assert(!equals(safe1, safe2));
    assert(!equals(safe2, safe1));
}
