// test data to understand clang AST regarding inheritance

class A {
    void a() {}
};

class B : public A {
    void b() {}
};

class C : public B {
    void c() {}
};

class VirtA {
    virtual ~VirtA() {}

    virtual void virtA() {}
};

class VirtB : public VirtA {
    virtual void virtB() {}
};

class VirtC : public VirtB {
    virtual void virtA() {}
    virtual void virtB() {}
};

namespace ns1 {

class Ns1A {
    void a() {}
};

namespace ns2 {

class Ns2B : public Ns1A {
};

} // NS: ns2

} // NS: ns1
