// test data to understand clang AST regarding inheritance

// expect gmock
class A {
public:
    virtual ~A() {}
    virtual void a() = 0;
};

// expect NO gmock
// even though A is an interface skipping B.
// this is considered the type of dangerous territory
// that we do not want to generate a gmock for.
// if the SUT take a ref to B then it is "stupid", not
// an interface. It should have been a ref to A.
class B : public A {
public:
    void b() {}
};

// expect NO gmock.
// See explanation for B.
class C : public B {
public:
    void c() {}
};

// expect gmock
class VirtA {
public:
    virtual ~VirtA() {}
    virtual void virtA() = 0;
};

// expect gmock with all from VirtA
class VirtB : public VirtA {
public:
    virtual ~VirtB() {}
    virtual void virtB() = 0;
};

// expect gmock with all from VirtA and VirtB
class VirtC : public VirtB {
public:
    virtual ~VirtC() {}
    virtual void virtC() = 0;
};

namespace ns1 {

// expect gmock
class Ns1A {
public:
    virtual ~Ns1A() {}
    virtual void a() = 0;
};

namespace ns2 {

// expect gmock, all from Ns1A.
// correct inheritance reference to Ns1A
class Ns2B : public Ns1A {
public:
    virtual ~Ns2B() {}
};

} // NS: ns2

} // NS: ns1
