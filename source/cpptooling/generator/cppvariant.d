// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: GPL
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Variant of C++ test double.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/
module cpptooling.generator.cppvariant;

import std.typecons : Typedef;
import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule, CppHModule;

import application.types;
import cpptooling.utility.nullvoid;

/// Control variouse aspectes of the analyze and generation like what nodes to
/// process.
@safe interface Controller {
    /// Query the controller with the filename of the AST node for a decision
    /// if it shall be processed.
    bool doFile(in string filename, in string info);

    /** A list of includes for the test double header.
     *
     * Part of the controller because they are dynamic, may change depending on
     * for example calls to doFile.
     */
    FileName[] getIncludes();

    /// Controls generation of google mock.
    bool doGoogleMock();

    /// Generate a pre_include header file from internal template?
    bool doPreIncludes();

    /// Generate a #include of the pre include header
    bool doIncludeOfPreIncludes();

    /// Generate a post_include header file from internal template?
    bool doPostIncludes();

    /// Generate a #include of the post include header
    bool doIncludeOfPostIncludes();
}

/// Parameters used during generation.
/// Important aspact that they do NOT change, therefore it is pure.
@safe pure interface Parameters {
    import std.typecons : Tuple;

    alias Files = Tuple!(FileName, "hdr", FileName, "impl", FileName,
        "globals", FileName, "gmock", FileName, "pre_incl", FileName, "post_incl");

    /// Source files used to generate the stub.
    FileName[] getIncludes();

    /// Output directory to store files in.
    DirName getOutputDirectory();

    /// Files to write generated test double data to.
    Files getFiles();

    /// Name affecting interface, namespace and output file.
    MainName getMainName();

    /** Namespace for the generated test double.
     *
     * Contains the adapter, C++ interface, gmock etc.
     */
    MainNs getMainNs();

    /** Name of the interface of the test double.
     *
     * Used in Adapter.
     */
    MainInterface getMainInterface();

    /** Prefix to use for the generated files.
     *
     * Affects both the filename and the preprocessor #include.
     */
    StubPrefix getFilePrefix();

    /// Prefix used for test artifacts.
    StubPrefix getArtifactPrefix();
}

/// Data produced by the generator like files.
@safe interface Products {
    /** Data pushed from the stub generator to be written to files.
     *
     * The put value is the code generation tree. It allows the caller of
     * StubGenerator to inject more data in the tree before writing. For
     * example a custom header.
     *
     * Params:
     *   fname = file the content is intended to be written to.
     *   hdr_data = data to write to the file.
     */
    void putFile(FileName fname, CppHModule hdr_data);

    /// ditto.
    void putFile(FileName fname, CppModule impl_data);

    /** During the translation phase the location of symbols that aren't
     * filtered out are pushed to the variant.
     *
     * It is intended that the variant control the #include directive strategy.
     * Just the files that was input?
     * Deduplicated list of files where the symbols was found?
     */
    void putLocation(FileName loc, LocationType type);
}

struct Generator {
    import std.typecons : Typedef;

    import cpptooling.data.representation : CppRoot;
    import cpptooling.utility.conv : str;

    static struct Modules {
        CppModule hdr;
        CppModule impl;
        CppModule gmock;
    }

    this(Controller ctrl, Parameters params, Products products) {
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
    }

    /** Process structural data to a test double.
     *
     * raw -> filter -> translate -> code gen.
     *
     * filters the structural data.
     * Controller is involved to allow filtering of identifiers in files.
     *
     * translate prepares the data for code generator.
     * On demand extra data is created. An example of on demand is --gmock.
     *
     * Code generation is a straight up translation.
     * Logical decisions should have been handled in earlier stages.
     */
    auto process(CppRoot root) {
        import cpptooling.data.representation : CppNamespace, CppNs;

        logger.trace("Raw:\n" ~ root.toString());

        auto fl = rawFilter(root, ctrl, products);
        logger.trace("Filtered:\n" ~ fl.toString());

        auto tr = translate(fl, ctrl, params);
        logger.trace("Translated to implementation:\n" ~ tr.toString());

        auto modules = makeCppModules();
        generate(tr, ctrl, params, modules);
        postProcess(ctrl, params, products, modules);
    }

private:
    Controller ctrl;
    Parameters params;
    Products products;

    auto makeCppModules() {
        import std.range : only;
        import std.algorithm : each;

        Modules m;
        //TODO how to do this with meta-programming and instrospection fo Modules?
        m.hdr = new CppModule;
        m.impl = new CppModule;
        m.gmock = new CppModule;
        return m;
    }

    static void postProcess(Controller ctrl, Parameters params, Products prods, Modules modules) {
        import cpptooling.generator.includes : convToIncludeGuard,
            generatetPreInclude, generatePostInclude;

        //TODO copied code from cstub. consider separating from this module to
        // allow reuse.
        static auto outputHdr(CppModule hdr, FileName fname) {
            auto o = CppHModule(convToIncludeGuard(fname));
            o.content.append(hdr);

            return o;
        }

        static auto output(CppModule code, FileName incl_fname) {
            import std.path : baseName;

            auto o = new CppModule;
            o.suppressIndent(1);
            o.include(incl_fname.str.baseName);
            o.sep(2);
            o.append(code);

            return o;
        }

        prods.putFile(params.getFiles.hdr, outputHdr(modules.hdr, params.getFiles.hdr));
        prods.putFile(params.getFiles.impl, output(modules.impl, params.getFiles.hdr));

        if (ctrl.doPreIncludes) {
            prods.putFile(params.getFiles.pre_incl, generatetPreInclude(params.getFiles.pre_incl));
        }
        if (ctrl.doPostIncludes) {
            prods.putFile(params.getFiles.post_incl, generatePostInclude(params.getFiles.post_incl));
        }

        if (ctrl.doGoogleMock) {
            import cpptooling.generator.gmock : generateGmockHdr;

            prods.putFile(params.getFiles.gmock,
                generateGmockHdr(params.getFiles.hdr, params.getFiles.gmock, modules.gmock));
        }
    }
}

private:
@safe:

import cpptooling.data.representation : CppRoot, CppClass, CppMethod, CppCtor,
    CppDtor, CFunction, CppNamespace, CxLocation;
import dsrcgen.cpp : E;

enum dummyLoc = CxLocation("<test double>", 0, 0);

enum ClassType {
    Normal,
    Adapter,
    Gmock
}

enum NamespaceType {
    Normal,
    TestDoubleSingleton,
    TestDouble
}

/** Structurally transformed the input to a stub implementation.
 *
 * Ignoring C functions and globals by ignoring the root ranges funcRange and
 * globalRange.
 *
 * Params:
 *  ctrl: removes according to directives via ctrl
 */
CppRoot rawFilter(CppRoot input, Controller ctrl, Products prod) {
    import std.algorithm : among, each, filter;
    import cpptooling.data.representation : VirtualType;

    auto raw = CppRoot(input.location);

    if (ctrl.doFile(input.location.file, "root " ~ input.location.toString)) {
        prod.putLocation(FileName(input.location.file), LocationType.Root);
    }

    // Assuming that namespaces are never duplicated at this stage.
    // The assumtion comes from the structore of the AST.
    // dfmt off
    input.namespaceRange
        .filter!(a => !a.isAnonymous)
        .each!(a => raw.put(rawFilter(a, ctrl, prod)));

    if (ctrl.doGoogleMock) {
        input.classRange
            .filter!(a => a.virtualType.among(VirtualType.Pure, VirtualType.Yes))
            .filter!(a => ctrl.doFile(a.location.file, cast(string) a.name ~ " " ~ a.location.toString))
            .each!((a) {prod.putLocation(FileName(a.location.file), LocationType.Leaf); raw.put(a);});
    }
    // dfmt on

    return raw;
}

/// Recursive filtering of namespaces to remove everything except free functions.
CppNamespace rawFilter(CppNamespace input, Controller ctrl, Products prod)
in {
    assert(!input.isAnonymous);
    assert(input.name.length > 0);
}
body {
    import std.algorithm : among, each, filter, map;
    import application.types : FileName;
    import cpptooling.data.representation : dedup, VirtualType;
    import cpptooling.generator.func : filterFunc = rawFilter;

    auto ns = CppNamespace.make(input.name);

    // dfmt off
    input.funcRange
        .dedup
        .filter!(a => ctrl.doFile(a.location.file, cast(string) a.name ~ " " ~ a.location.toString))
        .each!((a) {prod.putLocation(FileName(a.location.file), LocationType.Leaf); ns.put(a);});

    input.namespaceRange
        .filter!(a => !a.isAnonymous)
        .map!(a => rawFilter(a, ctrl, prod))
        .each!(a => ns.put(a));

    if (ctrl.doGoogleMock) {
        input.classRange
            .filter!(a => a.virtualType.among(VirtualType.Pure, VirtualType.Yes))
            .filter!(a => ctrl.doFile(a.location.file, cast(string) a.name ~ " " ~ a.location.toString))
            .each!((a) {prod.putLocation(FileName(a.location.file), LocationType.Leaf); ns.put(a);});
    }
    //dfmt on

    return ns;
}

CppRoot translate(CppRoot root, Controller ctrl, Parameters params) {
    import std.algorithm;
    import cpptooling.data.representation : VirtualType;

    auto r = CppRoot(root.location);

    // dfmt off
    root.namespaceRange
        .map!(a => translate(a, ctrl, params))
        .filter!(a => !a.isNull)
        .each!(a => r.put(a.get));

    root.classRange
        .each!((a) {a.setKind(ClassType.Gmock); r.put(a); });
    // dfmt on

    return r;
}

/** Translate namspaces and the content to test double implementations.
 *
 * Currently only cares about free functions.
 */
NullableVoid!CppNamespace translate(CppNamespace input, Controller ctrl, Parameters params) {
    import std.algorithm;
    import std.typecons : TypedefType;
    import cpptooling.data.representation;
    import cpptooling.generator.adapter : makeAdapter, makeSingleton;
    import cpptooling.generator.func : makeFuncInterface;
    import cpptooling.generator.gmock : makeGmock;

    static auto makeGmockInNs(CppClass c, Parameters params) {
        import cpptooling.data.representation;

        auto ns = CppNamespace.make(CppNs(cast(string) params.getMainNs));
        ns.setKind(NamespaceType.TestDouble);
        ns.put(makeGmock!ClassType(c));
        return ns;
    }

    auto ns = CppNamespace.make(input.name);

    if (!input.funcRange.empty) {
        ns.put(makeSingleton!NamespaceType(params.getMainNs, params.getMainInterface));
        input.funcRange.each!(a => ns.put(a));

        auto td_ns = CppNamespace.make(CppNs(cast(string) params.getMainNs));
        td_ns.setKind(NamespaceType.TestDouble);

        auto i_free_func = makeFuncInterface(input.funcRange, params.getMainInterface);
        td_ns.put(i_free_func);
        td_ns.put(makeAdapter!(MainInterface, ClassType)(params.getMainInterface));

        if (ctrl.doGoogleMock) {
            td_ns.put(makeGmock!ClassType(i_free_func));
        }

        ns.put(td_ns);
    }

    //dfmt off
    input.namespaceRange()
        .map!(a => translate(a, ctrl, params))
        .filter!(a => !a.isNull)
        .each!(a => ns.put(a.get));

    input.classRange
        .each!(a => ns.put(makeGmockInNs(a, params)));
    // dfmt on

    NullableVoid!CppNamespace rval;
    if (!ns.namespaceRange.empty || !ns.classRange.empty) {
        rval = ns;
    }

    return rval;
}

/** Translate the structure to code.
 *
 * order is important, affects code layout:
 *  - anonymouse for test double instance.
 *  - implementations using double.
 *  - adapter.
 */
void generate(CppRoot r, Controller ctrl, Parameters params, Generator.Modules modules)
in {
    assert(r.funcRange.empty);
}
body {
    import std.algorithm : each, filter;
    import cpptooling.generator.func : generateFuncImpl;
    import cpptooling.generator.gmock : generateGmock;
    import cpptooling.generator.includes : genCppIncl = generate;
    import cpptooling.utility.conv : str;

    genCppIncl(ctrl, params, modules.hdr);

    static void gmockGlobal(T)(T r, CppModule gmock, Parameters params) {
        // dfmt off
        r.filter!(a => cast(ClassType) a.kind == ClassType.Gmock)
            .each!(a => generateGmock(a, gmock, params));
        // dfmt on
    }

    // recursive to handle nested namespaces.
    // the singleton ns must be the first code generate or the impl can't
    // use the instance.
    static void eachNs(CppNamespace ns, Parameters params,
        Generator.Modules modules, CppModule impl_singleton) {

        auto inner = modules;
        CppModule inner_impl_singleton;

        final switch (cast(NamespaceType) ns.kind) with (NamespaceType) {
        case Normal:
            //TODO how to do this with meta-programming?
            inner.hdr = modules.hdr.namespace(ns.name.str);
            inner.hdr.suppressIndent(1);
            inner.impl = modules.impl.namespace(ns.name.str);
            inner.impl.suppressIndent(1);
            inner.gmock = modules.gmock.namespace(ns.name.str);
            inner.gmock.suppressIndent(1);
            inner_impl_singleton = inner.impl.base;
            inner_impl_singleton.suppressIndent(1);
            break;
        case TestDoubleSingleton:
            import cpptooling.generator.adapter : generateSingleton;

            generateSingleton(ns, impl_singleton);
            break;
        case TestDouble:
            generateNsTestDoubleHdr(ns, params, modules.hdr, modules.gmock);
            generateNsTestDoubleImpl(ns, params, modules.impl);
            break;
        }

        ns.funcRange.each!(a => generateFuncImpl(a, inner.impl));
        ns.namespaceRange.each!(a => eachNs(a, params, inner, inner_impl_singleton));
    }

    gmockGlobal(r.classRange, modules.gmock, params);
    // no singleton in global namespace thus null
    r.namespaceRange().each!(a => eachNs(a, params, modules, null));
}

void generateClassHdr(CppClass c, CppModule hdr, CppModule gmock, Parameters params) {
    import cpptooling.generator.classes : generateHdr;
    import cpptooling.generator.gmock : generateGmock;

    final switch (cast(ClassType) c.kind()) {
    case ClassType.Normal:
    case ClassType.Adapter:
        generateHdr(c, hdr);
        break;
    case ClassType.Gmock:
        generateGmock(c, gmock, params);
        break;
    }
}

void generateClassImpl(CppClass c, CppModule impl) {
    import cpptooling.generator.adapter : generateImplAdapter = generateImpl;

    final switch (cast(ClassType) c.kind()) {
    case ClassType.Normal:
        break;
    case ClassType.Adapter:
        generateImplAdapter(c, impl);
        break;
    case ClassType.Gmock:
        break;
    }
}

void generateNsTestDoubleHdr(CppNamespace ns, Parameters params, CppModule hdr, CppModule gmock) {
    import std.algorithm : each;
    import cpptooling.utility.conv : str;

    auto cpp_ns = hdr.namespace(ns.name.str);
    cpp_ns.suppressIndent(1);
    hdr.sep(2);

    ns.classRange().each!((a) { generateClassHdr(a, cpp_ns, gmock, params); });
}

void generateNsTestDoubleImpl(CppNamespace ns, Parameters params, CppModule impl) {
    import std.algorithm : each;
    import cpptooling.utility.conv : str;

    auto cpp_ns = impl.namespace(ns.name.str);
    cpp_ns.suppressIndent(1);
    impl.sep(2);

    ns.classRange().each!((a) { generateClassImpl(a, cpp_ns); });
}
