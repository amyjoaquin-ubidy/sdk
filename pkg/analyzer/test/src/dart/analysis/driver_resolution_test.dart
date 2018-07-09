// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/dart/ast/utilities.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/member.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:analyzer/src/generated/utilities_dart.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../../utils.dart';
import 'base.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AnalysisDriverResolutionTest);
  });
}

final isDynamicType = new TypeMatcher<DynamicTypeImpl>();

final isUndefinedType = new TypeMatcher<UndefinedTypeImpl>();

/**
 * Integration tests for resolution.
 */
@reflectiveTest
class AnalysisDriverResolutionTest extends BaseAnalysisDriverTest {
  AnalysisResult result;
  FindNode findNode;
  FindElement findElement;

  InterfaceType get doubleType => typeProvider.doubleType;

  InterfaceType get intType => typeProvider.intType;

  ClassElement get mapElement => typeProvider.mapType.element;

  InterfaceType get mapType => typeProvider.mapType;

  TypeProvider get typeProvider => result.unit.element.context.typeProvider;

  void assertElement(Expression node, Element expected) {
    Element actual = getNodeElement(node);
    expect(actual, same(expected));
  }

  void assertElementNull(Expression node) {
    Element actual = getNodeElement(node);
    expect(actual, isNull);
  }

  void assertMember(
      Expression node, String expectedDefiningType, Element expectedBase) {
    Member actual = getNodeElement(node);
    expect(actual.definingType.toString(), expectedDefiningType);
    expect(actual.baseElement, same(expectedBase));
  }

  void assertType(Expression expression, String expected) {
    DartType actual = expression.staticType;
    expect(actual?.toString(), expected);
  }

  /// Test that [argumentList] has exactly two type items `int` and `double`.
  void assertTypeArguments(
      TypeArgumentList argumentList, List<DartType> expectedTypes) {
    expect(argumentList.arguments, hasLength(expectedTypes.length));
    for (int i = 0; i < expectedTypes.length; i++) {
      _assertTypeNameSimple(argumentList.arguments[i], expectedTypes[i]);
    }
  }

  void assertTypeDynamic(Expression expression) {
    DartType actual = expression.staticType;
    expect(actual, isDynamicType);
  }

  /// Creates a function that checks that an expression is a reference to a top
  /// level variable with the given [name].
  void Function(Expression) checkTopVarRef(String name) {
    return (Expression e) {
      TopLevelVariableElement variable = _getTopLevelVariable(result, name);
      SimpleIdentifier node = e as SimpleIdentifier;
      expect(node.staticElement, same(variable.getter));
      expect(node.staticType, variable.type);
    };
  }

  /// Creates a function that checks that an expression is a named argument
  /// that references a top level variable with the given [name], where the
  /// name of the named argument is undefined.
  void Function(Expression) checkTopVarUndefinedNamedRef(String name) {
    return (Expression e) {
      TopLevelVariableElement variable = _getTopLevelVariable(result, name);
      NamedExpression named = e as NamedExpression;
      expect(named.staticType, variable.type);

      SimpleIdentifier nameIdentifier = named.name.label;
      expect(nameIdentifier.staticElement, isNull);
      if (useCFE) {
        expect(nameIdentifier.staticType, isDynamicType);
      }

      SimpleIdentifier arg2Node = named.expression;
      expect(arg2Node.staticElement, same(variable.getter));
      expect(arg2Node.staticType, variable.type);
    };
  }

  Element getNodeElement(Expression node) {
    if (node is AssignmentExpression) {
      return node.staticElement;
    } else if (node is Identifier) {
      return node.staticElement;
    } else if (node is IndexExpression) {
      return node.staticElement;
    } else if (node is PostfixExpression) {
      return node.staticElement;
    } else if (node is PrefixExpression) {
      return node.staticElement;
    } else {
      fail('Unsupported node: (${node.runtimeType}) $node');
    }
  }

  Future resolveTestFile() async {
    result = await driver.getResult(testFile);
    findNode = new FindNode(result);
    findElement = new FindElement(result);
  }

  test_adjacentStrings() async {
    String content = r'''
void main() {
  'aaa' 'bbb' 'ccc';
}
''';
    addTestFile(content);
    await resolveTestFile();

    List<Statement> statements = _getMainStatements(result);

    ExpressionStatement statement = statements[0];
    AdjacentStrings expression = statement.expression;
    expect(expression.staticType, typeProvider.stringType);
    expect(expression.strings, hasLength(3));

    StringLiteral literal_1 = expression.strings[0];
    expect(literal_1.staticType, typeProvider.stringType);

    StringLiteral literal_2 = expression.strings[1];
    expect(literal_2.staticType, typeProvider.stringType);

    StringLiteral literal_3 = expression.strings[2];
    expect(literal_3.staticType, typeProvider.stringType);
  }

  test_annotation() async {
    String content = r'''
const myAnnotation = 1;

@myAnnotation
class C {
  @myAnnotation
  int field1 = 2, field2 = 3;

  @myAnnotation
  C() {}

  @myAnnotation
  void method() {}
}

@myAnnotation
int topLevelVariable1 = 4, topLevelVariable2 = 5;

@myAnnotation
void topLevelFunction() {}
''';
    addTestFile(content);

    await resolveTestFile();

    TopLevelVariableDeclaration myDeclaration = result.unit.declarations[0];
    VariableDeclaration myVariable = myDeclaration.variables.variables[0];
    TopLevelVariableElement myElement = myVariable.element;

    void assertMyAnnotation(AnnotatedNode node) {
      Annotation annotation = node.metadata[0];
      expect(annotation.element, same(myElement.getter));

      SimpleIdentifier identifier_1 = annotation.name;
      expect(identifier_1.staticElement, same(myElement.getter));
      expect(identifier_1.staticType, typeProvider.intType);
    }

    {
      ClassDeclaration classNode = result.unit.declarations[1];
      assertMyAnnotation(classNode);

      {
        FieldDeclaration node = classNode.members[0];
        assertMyAnnotation(node);
      }

      {
        ConstructorDeclaration node = classNode.members[1];
        assertMyAnnotation(node);
      }

      {
        MethodDeclaration node = classNode.members[2];
        assertMyAnnotation(node);
      }
    }

    {
      TopLevelVariableDeclaration node = result.unit.declarations[2];
      assertMyAnnotation(node);
    }

    {
      FunctionDeclaration node = result.unit.declarations[3];
      assertMyAnnotation(node);
    }
  }

  test_annotation_onVariableList_constructor() async {
    String content = r'''
class C {
  final Object x;
  const C(this.x);
}
main() {
  @C(C(42))
  var foo = null;
}
''';
    addTestFile(content);

    await resolveTestFile();

    ClassDeclaration c = result.unit.declarations[0];
    ConstructorDeclaration constructor = c.members[1];
    ConstructorElement element = constructor.element;

    FunctionDeclaration main = result.unit.declarations[1];
    VariableDeclarationStatement statement =
        (main.functionExpression.body as BlockFunctionBody).block.statements[0];
    Annotation annotation = statement.variables.metadata[0];
    expect(annotation.element, same(element));

    SimpleIdentifier identifier_1 = annotation.name;
    expect(identifier_1.staticElement, same(c.element));
  }

  test_annotation_onVariableList_topLevelVariable() async {
    String content = r'''
const myAnnotation = 1;

class C {
  void method() {
    @myAnnotation
    int var1 = 4, var2 = 5;
  }
}
''';
    addTestFile(content);

    await resolveTestFile();

    TopLevelVariableDeclaration myDeclaration = result.unit.declarations[0];
    VariableDeclaration myVariable = myDeclaration.variables.variables[0];
    TopLevelVariableElement myElement = myVariable.element;

    ClassDeclaration classNode = result.unit.declarations[1];
    MethodDeclaration node = classNode.members[0];
    VariableDeclarationStatement statement =
        (node.body as BlockFunctionBody).block.statements[0];
    Annotation annotation = statement.variables.metadata[0];
    expect(annotation.element, same(myElement.getter));

    SimpleIdentifier identifier_1 = annotation.name;
    expect(identifier_1.staticElement, same(myElement.getter));
    expect(identifier_1.staticType, typeProvider.intType);
  }

  test_annotation_prefixed_classField() async {
    var a = _p('/test/lib/a.dart');
    provider.newFile(a, r'''
class A {
  static const a = 1;
}
''');
    addTestFile(r'''
import 'a.dart' as p;

@p.A.a
main() {}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ImportElement aImport = unit.element.library.imports[0];
    PrefixElement aPrefix = aImport.prefix;
    LibraryElement aLibrary = aImport.importedLibrary;

    CompilationUnitElement aUnitElement = aLibrary.definingCompilationUnit;
    ClassElement aClass = aUnitElement.getType('A');
    var aGetter = aClass.getField('a').getter;

    Annotation annotation = unit.declarations[0].metadata.single;
    expect(annotation.element, same(aGetter));
    PrefixedIdentifier prefixed = annotation.name;

    expect(prefixed.prefix.staticElement, same(aPrefix));
    expect(prefixed.prefix.staticType, isNull);

    expect(prefixed.identifier.staticElement, same(aClass));
    expect(prefixed.prefix.staticType, isNull);

    expect(annotation.constructorName.staticElement, aGetter);
    expect(annotation.constructorName.staticType, typeProvider.intType);

    expect(annotation.arguments, isNull);
  }

  test_annotation_prefixed_constructor() async {
    var a = _p('/test/lib/a.dart');
    provider.newFile(a, r'''
class A {
  const A(int a, {int b});
}
''');
    addTestFile(r'''
import 'a.dart' as p;

@p.A(1, b: 2)
main() {}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;

    ImportElement aImport = unit.element.library.imports[0];
    PrefixElement aPrefix = aImport.prefix;
    LibraryElement aLibrary = aImport.importedLibrary;

    CompilationUnitElement aUnitElement = aLibrary.definingCompilationUnit;
    ClassElement aClass = aUnitElement.getType('A');
    ConstructorElement constructor = aClass.unnamedConstructor;

    Annotation annotation = unit.declarations[0].metadata.single;
    expect(annotation.element, same(constructor));
    PrefixedIdentifier prefixed = annotation.name;

    expect(prefixed.prefix.staticElement, same(aPrefix));
    expect(prefixed.prefix.staticType, isNull);

    expect(prefixed.identifier.staticElement, same(aClass));
    expect(prefixed.prefix.staticType, isNull);

    expect(annotation.constructorName, isNull);

    var arguments = annotation.arguments.arguments;
    var parameters = constructor.parameters;
    _assertArgumentToParameter(arguments[0], parameters[0]);
    _assertArgumentToParameter(arguments[1], parameters[1]);
  }

  test_annotation_prefixed_constructor_named() async {
    var a = _p('/test/lib/a.dart');
    provider.newFile(a, r'''
class A {
  const A.named(int a, {int b});
}
''');
    addTestFile(r'''
import 'a.dart' as p;

@p.A.named(1, b: 2)
main() {}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;

    ImportElement aImport = unit.element.library.imports[0];
    PrefixElement aPrefix = aImport.prefix;
    LibraryElement aLibrary = aImport.importedLibrary;

    CompilationUnitElement aUnitElement = aLibrary.definingCompilationUnit;
    ClassElement aClass = aUnitElement.getType('A');
    ConstructorElement constructor = aClass.getNamedConstructor('named');

    Annotation annotation = unit.declarations[0].metadata.single;
    expect(annotation.element, same(constructor));
    PrefixedIdentifier prefixed = annotation.name;

    expect(prefixed.prefix.staticElement, same(aPrefix));
    expect(prefixed.prefix.staticType, isNull);

    expect(prefixed.identifier.staticElement, same(aClass));
    expect(prefixed.prefix.staticType, isNull);

    SimpleIdentifier constructorName = annotation.constructorName;
    expect(constructorName.staticElement, same(constructor));
    expect(constructorName.staticType.toString(), '(int, {b: int}) → A');

    var arguments = annotation.arguments.arguments;
    var parameters = constructor.parameters;
    _assertArgumentToParameter(arguments[0], parameters[0]);
    _assertArgumentToParameter(arguments[1], parameters[1]);
  }

  test_annotation_prefixed_topLevelVariable() async {
    var a = _p('/test/lib/a.dart');
    provider.newFile(a, r'''
const topAnnotation = 1;
''');
    addTestFile(r'''
import 'a.dart' as p;

@p.topAnnotation
main() {}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;

    ImportElement aImport = unit.element.library.imports[0];
    PrefixElement aPrefix = aImport.prefix;
    LibraryElement aLibrary = aImport.importedLibrary;

    CompilationUnitElement aUnitElement = aLibrary.definingCompilationUnit;
    var topAnnotation = aUnitElement.topLevelVariables[0].getter;

    Annotation annotation = unit.declarations[0].metadata.single;
    expect(annotation.element, same(topAnnotation));
    PrefixedIdentifier prefixed = annotation.name;

    expect(prefixed.prefix.staticElement, same(aPrefix));
    expect(prefixed.prefix.staticType, isNull);

    expect(prefixed.identifier.staticElement, same(topAnnotation));
    expect(prefixed.prefix.staticType, isNull);

    expect(annotation.constructorName, isNull);
    expect(annotation.arguments, isNull);
  }

  test_annotation_unprefixed_classField() async {
    addTestFile(r'''
@A.a
main() {}

class A {
  static const a = 1;
}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    CompilationUnitElement unitElement = unit.element;
    var typeProvider = unitElement.context.typeProvider;

    ClassElement aClass = unitElement.getType('A');
    var aGetter = aClass.getField('a').getter;

    Annotation annotation = unit.declarations[0].metadata.single;
    expect(annotation.element, same(aGetter));
    PrefixedIdentifier prefixed = annotation.name;

    expect(prefixed.prefix.staticElement, same(aClass));
    expect(prefixed.prefix.staticType, aClass.type);

    expect(prefixed.identifier.staticElement, same(aGetter));
    expect(prefixed.identifier.staticType, typeProvider.intType);

    expect(annotation.constructorName, isNull);
    expect(annotation.arguments, isNull);
  }

  test_annotation_unprefixed_constructor() async {
    addTestFile(r'''
@A(1, b: 2)
main() {}

class A {
  const A(int a, {int b});
}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    CompilationUnitElement unitElement = unit.element;

    ClassElement aClass = unitElement.getType('A');
    ConstructorElement constructor = aClass.unnamedConstructor;

    Annotation annotation = unit.declarations[0].metadata.single;
    expect(annotation.element, same(constructor));

    SimpleIdentifier name = annotation.name;
    expect(name.staticElement, same(aClass));

    expect(annotation.constructorName, isNull);

    var arguments = annotation.arguments.arguments;
    var parameters = constructor.parameters;
    _assertArgumentToParameter(arguments[0], parameters[0]);
    _assertArgumentToParameter(arguments[1], parameters[1]);
  }

  test_annotation_unprefixed_constructor_named() async {
    addTestFile(r'''
@A.named(1, b: 2)
main() {}

class A {
  const A.named(int a, {int b});
}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    CompilationUnitElement unitElement = unit.element;

    ClassElement aClass = unitElement.getType('A');
    ConstructorElement constructor = aClass.constructors.single;

    Annotation annotation = unit.declarations[0].metadata.single;
    expect(annotation.element, same(constructor));
    PrefixedIdentifier prefixed = annotation.name;

    expect(prefixed.prefix.staticElement, same(aClass));
    expect(prefixed.prefix.staticType, aClass.type);

    expect(prefixed.identifier.staticElement, same(constructor));
    expect(prefixed.identifier.staticType.toString(), '(int, {b: int}) → A');

    expect(annotation.constructorName, isNull);

    var arguments = annotation.arguments.arguments;
    var parameters = constructor.parameters;
    _assertArgumentToParameter(arguments[0], parameters[0]);
    _assertArgumentToParameter(arguments[1], parameters[1]);
  }

  test_annotation_unprefixed_constructor_withNestedConstructorInvocation() async {
    addTestFile('''
class C {
  const C();
}
class D {
  final C c;
  const D(this.c);
}
@D(const C())
f() {}
''');
    await resolveTestFile();
    var elementC = AstFinder.getClass(result.unit, 'C').element;
    var constructorC = elementC.constructors[0];
    var elementD = AstFinder.getClass(result.unit, 'D').element;
    var constructorD = elementD.constructors[0];
    var atD = AstFinder.getTopLevelFunction(result.unit, 'f').metadata[0];
    InstanceCreationExpression constC = atD.arguments.arguments[0];

    expect(atD.name.staticElement, elementD);
    expect(atD.element, constructorD);

    expect(constC.staticElement, constructorC);
    expect(constC.staticType, elementC.type);

    expect(constC.constructorName.staticElement, constructorC);
    expect(constC.constructorName.type.type, elementC.type);
  }

  test_annotation_unprefixed_topLevelVariable() async {
    String content = r'''
const annotation_1 = 1;
const annotation_2 = 1;
@annotation_1
@annotation_2
void main() {
  print(42);
}
''';
    addTestFile(content);

    await resolveTestFile();

    TopLevelVariableDeclaration declaration_1 = result.unit.declarations[0];
    VariableDeclaration variable_1 = declaration_1.variables.variables[0];
    TopLevelVariableElement element_1 = variable_1.element;

    TopLevelVariableDeclaration declaration_2 = result.unit.declarations[1];
    VariableDeclaration variable_2 = declaration_2.variables.variables[0];
    TopLevelVariableElement element_2 = variable_2.element;

    FunctionDeclaration main = result.unit.declarations[2];

    Annotation annotation_1 = main.metadata[0];
    expect(annotation_1.element, same(element_1.getter));

    SimpleIdentifier identifier_1 = annotation_1.name;
    expect(identifier_1.staticElement, same(element_1.getter));
    expect(identifier_1.staticType, typeProvider.intType);

    Annotation annotation_2 = main.metadata[1];
    expect(annotation_2.element, same(element_2.getter));

    SimpleIdentifier identifier_2 = annotation_2.name;
    expect(identifier_2.staticElement, same(element_2.getter));
    expect(identifier_2.staticType, typeProvider.intType);
  }

  test_asExpression() async {
    String content = r'''
void main() {
  num v = 42;
  v as int;
}
''';
    addTestFile(content);

    await resolveTestFile();
    expect(result.path, testFile);
    expect(result.errors, isEmpty);

    NodeList<Statement> statements = _getMainStatements(result);

    // num v = 42;
    VariableElement vElement;
    {
      VariableDeclarationStatement statement = statements[0];
      vElement = statement.variables.variables[0].name.staticElement;
      expect(vElement.type, typeProvider.numType);
    }

    // v as int;
    {
      ExpressionStatement statement = statements[1];
      AsExpression asExpression = statement.expression;
      expect(asExpression.staticType, typeProvider.intType);

      SimpleIdentifier target = asExpression.expression;
      expect(target.staticElement, vElement);
      expect(target.staticType, typeProvider.numType);

      TypeName intName = asExpression.type;
      expect(intName.name.staticElement, typeProvider.intType.element);
      expect(intName.name.staticType, typeProvider.intType);
    }
  }

  test_assignment_to_final_parameter() async {
    addTestFile('''
f(final int x) {
  x += 2;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var xElement = findNode.simple('x)').staticElement;
    expect(xElement, isNotNull);
    var xReference = findNode.simple('x +=');
    expect(xReference.staticElement, same(xElement));
    expect(xReference.staticType.toString(), 'int');
  }

  test_assignment_to_final_variable_local() async {
    addTestFile('''
main() {
  final x = 1;
  x += 2;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var xElement = findNode.simple('x =').staticElement;
    expect(xElement, isNotNull);
    var xReference = findNode.simple('x +=');
    expect(xReference.staticElement, same(xElement));
    expect(xReference.staticType.toString(), 'int');
  }

  test_assignment_to_getter_instance_direct() async {
    addTestFile('''
class C {
  int get x => 0;
}
f(C c) {
  c.x += 2;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var xElement = findElement.getter('x');
    expect(xElement, isNotNull);
    var xReference = findNode.simple('x +=');
    expect(xReference.staticElement, useCFE ? isNull : same(xElement));
    expect(xReference.staticType.toString(), useCFE ? 'dynamic' : 'int');
  }

  test_assignment_to_getter_instance_via_implicit_this() async {
    addTestFile('''
class C {
  int get x => 0;
  f() {
    x += 2;
  }
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var xElement = findElement.getter('x');
    expect(xElement, isNotNull);
    var xReference = findNode.simple('x +=');
    expect(xReference.staticElement, useCFE ? isNull : same(xElement));
    expect(xReference.staticType.toString(), useCFE ? 'dynamic' : 'int');
  }

  test_assignment_to_getter_static_direct() async {
    addTestFile('''
class C {
  static int get x => 0;
}
main() {
  C.x += 2;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var xElement = findElement.getter('x');
    expect(xElement, isNotNull);
    var xReference = findNode.simple('x +=');
    expect(xReference.staticElement, useCFE ? isNull : same(xElement));
    expect(xReference.staticType.toString(), useCFE ? 'dynamic' : 'int');
  }

  test_assignment_to_getter_static_via_scope() async {
    addTestFile('''
class C {
  static int get x => 0;
  f() {
    x += 2;
  }
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var xElement = findElement.getter('x');
    expect(xElement, isNotNull);
    var xReference = findNode.simple('x +=');
    expect(xReference.staticElement, useCFE ? isNull : same(xElement));
    expect(xReference.staticType.toString(), useCFE ? 'dynamic' : 'int');
  }

  test_assignment_to_getter_top_level() async {
    addTestFile('''
int get x => 0;
main() {
  x += 2;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var xElement = findElement.topGet('x');
    expect(xElement, isNotNull);
    var xReference = findNode.simple('x +=');
    expect(xReference.staticElement, useCFE ? isNull : same(xElement));
    expect(xReference.staticType.toString(), useCFE ? 'dynamic' : 'int');
  }

  test_assignment_to_prefix() async {
    var a = _p('/test/lib/a.dart');
    provider.newFile(a, '''
var x = 0;
''');
    addTestFile('''
import 'a.dart' as p;
main() {
  p += 2;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var pElement = findElement.prefix('p');
    expect(pElement, isNotNull);
    var pReference = findNode.simple('p +=');
    expect(pReference.staticElement, same(pElement));
    expect(pReference.staticType, isNull);
  }

  test_assignmentExpression_compound_indexExpression() async {
    String content = r'''
main() {
  var items = <num>[1, 2, 3];
  items[0] += 4;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;

    var typeProvider = unit.element.context.typeProvider;
    InterfaceType numType = typeProvider.numType;
    InterfaceType intType = typeProvider.intType;
    InterfaceType listType = typeProvider.listType;
    InterfaceType listNumType = listType.instantiate([numType]);

    List<Statement> mainStatements = _getMainStatements(result);

    VariableElement itemsElement;
    {
      VariableDeclarationStatement statement = mainStatements[0];
      VariableDeclaration itemsNode = statement.variables.variables[0];
      itemsElement = itemsNode.element;
      expect(itemsElement.type, listNumType);
    }

    {
      ExpressionStatement statement = mainStatements[1];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.operator.type, TokenType.PLUS_EQ);
      expect(assignment.staticElement, isNotNull);
      expect(assignment.staticElement.name, '+');
      expect(assignment.staticType, typeProvider.numType); // num + int = num

      IndexExpression indexExpression = assignment.leftHandSide;
      expect(indexExpression.staticType, numType);
      expect(indexExpression.index.staticType, intType);

      MethodMember actualElement = indexExpression.staticElement;
      MethodMember expectedElement = listNumType.getMethod('[]=');
      expect(actualElement.name, '[]=');
      expect(actualElement.baseElement, same(expectedElement.baseElement));
      expect(actualElement.returnType, VoidTypeImpl.instance);
      expect(actualElement.parameters[0].type, intType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_compound_local() async {
    String content = r'''
main() {
  num v = 0;
  v += 3;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> mainStatements = _getMainStatements(result);

    VariableElement v;
    {
      VariableDeclarationStatement statement = mainStatements[0];
      v = statement.variables.variables[0].element;
      expect(v.type, typeProvider.numType);
    }

    {
      ExpressionStatement statement = mainStatements[1];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.operator.type, TokenType.PLUS_EQ);
      expect(assignment.staticElement, isNotNull);
      expect(assignment.staticElement.name, '+');
      expect(assignment.staticType, typeProvider.numType); // num + int = num

      SimpleIdentifier left = assignment.leftHandSide;
      expect(left.staticElement, same(v));
      expect(left.staticType, typeProvider.numType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_compound_prefixedIdentifier() async {
    String content = r'''
main() {
  var c = new C();
  c.f += 2;
}
class C {
  num f;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cClassDeclaration = unit.declarations[1];
    ClassElement cClassElement = cClassDeclaration.element;
    FieldElement fElement = cClassElement.getField('f');

    List<Statement> mainStatements = _getMainStatements(result);

    VariableElement c;
    {
      VariableDeclarationStatement statement = mainStatements[0];
      c = statement.variables.variables[0].element;
      expect(c.type, cClassElement.type);
    }

    {
      ExpressionStatement statement = mainStatements[1];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.operator.type, TokenType.PLUS_EQ);
      expect(assignment.staticElement, isNotNull);
      expect(assignment.staticElement.name, '+');
      expect(assignment.staticType, typeProvider.numType); // num + int = num

      PrefixedIdentifier left = assignment.leftHandSide;
      expect(left.staticElement, same(fElement.setter));
      expect(left.staticType, typeProvider.numType);

      expect(left.prefix.staticElement, c);
      expect(left.prefix.staticType, cClassElement.type);

      expect(left.identifier.staticElement, same(fElement.setter));
      expect(left.identifier.staticType, typeProvider.numType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_compound_propertyAccess() async {
    String content = r'''
main() {
  new C().f += 2;
}
class C {
  num f;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cClassDeclaration = unit.declarations[1];
    ClassElement cClassElement = cClassDeclaration.element;
    FieldElement fElement = cClassElement.getField('f');

    List<Statement> mainStatements = _getMainStatements(result);

    {
      ExpressionStatement statement = mainStatements[0];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.operator.type, TokenType.PLUS_EQ);
      expect(assignment.staticElement, isNotNull);
      expect(assignment.staticElement.name, '+');
      expect(assignment.staticType, typeProvider.numType); // num + int = num

      PropertyAccess left = assignment.leftHandSide;
      expect(left.staticType, typeProvider.numType);

      InstanceCreationExpression newC = left.target;
      expect(newC.staticElement, cClassElement.unnamedConstructor);

      expect(left.propertyName.staticElement, same(fElement.setter));
      expect(left.propertyName.staticType, typeProvider.numType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_nullAware_local() async {
    String content = r'''
main() {
  String v;
  v ??= 'test';
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> mainStatements = _getMainStatements(result);

    VariableElement v;
    {
      VariableDeclarationStatement statement = mainStatements[0];
      v = statement.variables.variables[0].element;
    }

    {
      ExpressionStatement statement = mainStatements[1];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.operator.type, TokenType.QUESTION_QUESTION_EQ);
      expect(assignment.staticElement, isNull);
      expect(assignment.staticType, typeProvider.stringType);

      SimpleIdentifier left = assignment.leftHandSide;
      expect(left.staticElement, same(v));
      expect(left.staticType, typeProvider.stringType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.stringType);
    }
  }

  test_assignmentExpression_propertyAccess_forwardingStub() async {
    String content = r'''
class A {
  int f;
}
abstract class I<T> {
  T f;
}
class B extends A implements I<int> {}
main() {
  new B().f = 1;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration aNode = unit.declarations[0];
    ClassElement aElement = aNode.element;
    FieldElement fElement = aElement.getField('f');

    ClassDeclaration bNode = unit.declarations[2];
    ClassElement bElement = bNode.element;

    List<Statement> mainStatements = _getMainStatements(result);
    ExpressionStatement statement = mainStatements[0];

    AssignmentExpression assignment = statement.expression;
    expect(assignment.staticType, typeProvider.intType);

    PropertyAccess left = assignment.leftHandSide;
    expect(left.staticType, typeProvider.intType);

    InstanceCreationExpression newB = left.target;
    expect(newB.staticElement, bElement.unnamedConstructor);

    expect(left.propertyName.staticElement, same(fElement.setter));
    expect(left.propertyName.staticType, typeProvider.intType);

    Expression right = assignment.rightHandSide;
    expect(right.staticType, typeProvider.intType);
  }

  test_assignmentExpression_simple_indexExpression() async {
    String content = r'''
main() {
  var items = <int>[1, 2, 3];
  items[0] = 4;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;

    var typeProvider = unit.element.context.typeProvider;
    InterfaceType intType = typeProvider.intType;
    InterfaceType listType = typeProvider.listType;
    InterfaceType listIntType = listType.instantiate([intType]);

    List<Statement> mainStatements = _getMainStatements(result);

    VariableElement itemsElement;
    {
      VariableDeclarationStatement statement = mainStatements[0];
      VariableDeclaration itemsNode = statement.variables.variables[0];
      itemsElement = itemsNode.element;
      expect(itemsElement.type, listIntType);
    }

    {
      ExpressionStatement statement = mainStatements[1];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.operator.type, TokenType.EQ);
      expect(assignment.staticElement, isNull);
      expect(assignment.staticType, typeProvider.intType);

      IndexExpression indexExpression = assignment.leftHandSide;
      expect(indexExpression.staticType, intType);
      expect(indexExpression.index.staticType, intType);

      MethodMember actualElement = indexExpression.staticElement;
      MethodMember expectedElement = listIntType.getMethod('[]=');
      expect(actualElement.name, '[]=');
      expect(actualElement.baseElement, same(expectedElement.baseElement));
      expect(actualElement.returnType, VoidTypeImpl.instance);
      expect(actualElement.parameters[0].type, intType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_simple_instanceField_unqualified() async {
    String content = r'''
class C {
  num f = 0;
  foo() {
    f = 2;
  }
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cDeclaration = unit.declarations[0];
    FieldElement fElement = cDeclaration.element.fields[0];

    MethodDeclaration fooDeclaration = cDeclaration.members[1];
    BlockFunctionBody fooBody = fooDeclaration.body;

    {
      ExpressionStatement statement = fooBody.block.statements[0];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.operator.type, TokenType.EQ);
      expect(assignment.staticElement, isNull);
      expect(assignment.staticType, typeProvider.intType);

      SimpleIdentifier left = assignment.leftHandSide;
      expect(left.staticElement, same(fElement.setter));
      expect(left.staticType, typeProvider.numType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_simple_local() async {
    String content = r'''
main() {
  num v = 0;
  v = 2;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> mainStatements = _getMainStatements(result);

    VariableElement v;
    {
      VariableDeclarationStatement statement = mainStatements[0];
      v = statement.variables.variables[0].element;
      expect(v.type, typeProvider.numType);
    }

    {
      ExpressionStatement statement = mainStatements[1];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.operator.type, TokenType.EQ);
      expect(assignment.staticElement, isNull);
      expect(assignment.staticType, typeProvider.intType);

      SimpleIdentifier left = assignment.leftHandSide;
      expect(left.staticElement, same(v));
      expect(left.staticType, typeProvider.numType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_simple_prefixedIdentifier() async {
    String content = r'''
main() {
  var c = new C();
  c.f = 2;
}
class C {
  num f;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cClassDeclaration = unit.declarations[1];
    ClassElement cClassElement = cClassDeclaration.element;
    FieldElement fElement = cClassElement.getField('f');

    List<Statement> mainStatements = _getMainStatements(result);

    VariableElement c;
    {
      VariableDeclarationStatement statement = mainStatements[0];
      c = statement.variables.variables[0].element;
      expect(c.type, cClassElement.type);
    }

    {
      ExpressionStatement statement = mainStatements[1];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.staticType, typeProvider.intType);

      PrefixedIdentifier left = assignment.leftHandSide;
      expect(left.staticElement, same(fElement.setter));
      expect(left.staticType, typeProvider.numType);

      expect(left.prefix.staticElement, c);
      expect(left.prefix.staticType, cClassElement.type);

      expect(left.identifier.staticElement, same(fElement.setter));
      expect(left.identifier.staticType, typeProvider.numType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_simple_prefixedIdentifier_staticField() async {
    String content = r'''
main() {
  C.f = 2;
}
class C {
  static num f;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cClassDeclaration = unit.declarations[1];
    ClassElement cClassElement = cClassDeclaration.element;
    FieldElement fElement = cClassElement.getField('f');

    List<Statement> mainStatements = _getMainStatements(result);

    {
      ExpressionStatement statement = mainStatements[0];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.staticType, typeProvider.intType);

      PrefixedIdentifier left = assignment.leftHandSide;
      expect(left.staticElement, same(fElement.setter));
      expect(left.staticType, typeProvider.numType);

      expect(left.prefix.staticElement, cClassElement);
      expect(left.prefix.staticType, cClassElement.type);

      expect(left.identifier.staticElement, same(fElement.setter));
      expect(left.identifier.staticType, typeProvider.numType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_simple_propertyAccess() async {
    String content = r'''
main() {
  new C().f = 2;
}
class C {
  num f;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cClassDeclaration = unit.declarations[1];
    ClassElement cClassElement = cClassDeclaration.element;
    FieldElement fElement = cClassElement.getField('f');

    List<Statement> mainStatements = _getMainStatements(result);

    {
      ExpressionStatement statement = mainStatements[0];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.staticType, typeProvider.intType);

      PropertyAccess left = assignment.leftHandSide;
      expect(left.staticType, typeProvider.numType);

      InstanceCreationExpression newC = left.target;
      expect(newC.staticElement, cClassElement.unnamedConstructor);

      expect(left.propertyName.staticElement, same(fElement.setter));
      expect(left.propertyName.staticType, typeProvider.numType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_simple_propertyAccess_chained() async {
    String content = r'''
main() {
  var a = new A();
  a.b.f = 2;
}
class A {
  B b;
}
class B {
  num f;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration aClassDeclaration = unit.declarations[1];
    ClassElement aClassElement = aClassDeclaration.element;
    FieldElement bElement = aClassElement.getField('b');

    ClassDeclaration bClassDeclaration = unit.declarations[2];
    ClassElement bClassElement = bClassDeclaration.element;
    FieldElement fElement = bClassElement.getField('f');

    List<Statement> mainStatements = _getMainStatements(result);

    VariableElement a;
    {
      VariableDeclarationStatement statement = mainStatements[0];
      a = statement.variables.variables[0].element;
      expect(a.type, aClassElement.type);
    }

    {
      ExpressionStatement statement = mainStatements[1];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.staticType, typeProvider.intType);

      PropertyAccess fAccess = assignment.leftHandSide;
      expect(fAccess.propertyName.name, 'f');
      expect(fAccess.propertyName.staticElement, same(fElement.setter));
      expect(fAccess.propertyName.staticType, typeProvider.numType);

      PrefixedIdentifier bAccess = fAccess.target;
      expect(bAccess.identifier.name, 'b');
      expect(bAccess.identifier.staticElement, same(bElement.getter));
      expect(bAccess.identifier.staticType, bClassElement.type);

      SimpleIdentifier aIdentifier = bAccess.prefix;
      expect(aIdentifier.name, 'a');
      expect(aIdentifier.staticElement, a);
      expect(aIdentifier.staticType, aClassElement.type);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_simple_propertyAccess_setter() async {
    String content = r'''
main() {
  new C().f = 2;
}
class C {
  void set f(num _) {}
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cClassDeclaration = unit.declarations[1];
    ClassElement cClassElement = cClassDeclaration.element;
    FieldElement fElement = cClassElement.getField('f');

    List<Statement> mainStatements = _getMainStatements(result);

    {
      ExpressionStatement statement = mainStatements[0];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.staticType, typeProvider.intType);

      PropertyAccess left = assignment.leftHandSide;
      expect(left.staticType, typeProvider.numType);

      InstanceCreationExpression newC = left.target;
      expect(newC.staticElement, cClassElement.unnamedConstructor);

      expect(left.propertyName.staticElement, same(fElement.setter));
      expect(left.propertyName.staticType, typeProvider.numType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_simple_staticField_unqualified() async {
    String content = r'''
class C {
  static num f = 0;
  foo() {
    f = 2;
  }
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cDeclaration = unit.declarations[0];
    FieldElement fElement = cDeclaration.element.fields[0];

    MethodDeclaration fooDeclaration = cDeclaration.members[1];
    BlockFunctionBody fooBody = fooDeclaration.body;

    {
      ExpressionStatement statement = fooBody.block.statements[0];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.operator.type, TokenType.EQ);
      expect(assignment.staticElement, isNull);
      expect(assignment.staticType, typeProvider.intType);

      SimpleIdentifier left = assignment.leftHandSide;
      expect(left.staticElement, same(fElement.setter));
      expect(left.staticType, typeProvider.numType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_assignmentExpression_simple_topLevelVariable() async {
    String content = r'''
main() {
  v = 2;
}
num v = 0;
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    TopLevelVariableElement v;
    {
      TopLevelVariableDeclaration declaration = unit.declarations[1];
      v = declaration.variables.variables[0].element;
      expect(v.type, typeProvider.numType);
    }

    List<Statement> mainStatements = _getMainStatements(result);
    {
      ExpressionStatement statement = mainStatements[0];

      AssignmentExpression assignment = statement.expression;
      expect(assignment.operator.type, TokenType.EQ);
      expect(assignment.staticElement, isNull);
      expect(assignment.staticType, typeProvider.intType);

      SimpleIdentifier left = assignment.leftHandSide;
      expect(left.staticElement, same(v.setter));
      expect(left.staticType, typeProvider.numType);

      Expression right = assignment.rightHandSide;
      expect(right.staticType, typeProvider.intType);
    }
  }

  test_binaryExpression() async {
    String content = r'''
main() {
  var v = 1 + 2;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> mainStatements = _getMainStatements(result);

    VariableDeclarationStatement statement = mainStatements[0];
    VariableDeclaration vNode = statement.variables.variables[0];
    VariableElement vElement = vNode.element;
    expect(vElement.type, typeProvider.intType);

    BinaryExpression value = vNode.initializer;
    expect(value.leftOperand.staticType, typeProvider.intType);
    expect(value.rightOperand.staticType, typeProvider.intType);
    expect(value.staticElement.name, '+');
    expect(value.staticType, typeProvider.intType);
  }

  test_binaryExpression_ifNull() async {
    String content = r'''
main() {
  1.2 ?? 3;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> mainStatements = _getMainStatements(result);

    ExpressionStatement statement = mainStatements[0];
    BinaryExpression binary = statement.expression;
    expect(binary.operator.type, TokenType.QUESTION_QUESTION);
    expect(binary.staticElement, isNull);
    expect(binary.staticType, typeProvider.numType);

    expect(binary.leftOperand.staticType, typeProvider.doubleType);
    expect(binary.rightOperand.staticType, typeProvider.intType);
  }

  test_binaryExpression_logical() async {
    addTestFile(r'''
main() {
  true && true;
  true || true;
}
''');
    await resolveTestFile();

    List<Statement> statements = _getMainStatements(result);

    {
      ExpressionStatement statement = statements[0];
      BinaryExpression binaryExpression = statement.expression;
      expect(binaryExpression.staticElement, isNull);
      expect(binaryExpression.staticType, typeProvider.boolType);
    }

    {
      ExpressionStatement statement = statements[1];
      BinaryExpression binaryExpression = statement.expression;
      expect(binaryExpression.staticElement, isNull);
      expect(binaryExpression.staticType, typeProvider.boolType);
    }
  }

  test_binaryExpression_notEqual() async {
    String content = r'''
main() {
  1 != 2;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];
    BinaryExpression expression = statement.expression;
    expect(expression.operator.type, TokenType.BANG_EQ);
    expect(expression.leftOperand.staticType, typeProvider.intType);
    expect(expression.rightOperand.staticType, typeProvider.intType);
    expect(expression.staticElement.name, '==');
    expect(expression.staticType, typeProvider.boolType);
  }

  test_cascadeExpression() async {
    String content = r'''
void main() {
  new A()..a()..b();
}
class A {
  void a() {}
  void b() {}
}
''';
    addTestFile(content);
    await resolveTestFile();

    List<Statement> statements = _getMainStatements(result);

    ExpressionStatement statement = statements[0];
    CascadeExpression expression = statement.expression;
    expect(expression.target.staticType, isNotNull);
    NodeList<Expression> sections = expression.cascadeSections;

    MethodInvocation a = sections[0];
    expect(a.methodName.staticElement, isNotNull);
    expect(a.staticType, isNotNull);

    MethodInvocation b = sections[1];
    expect(b.methodName.staticElement, isNotNull);
    expect(b.staticType, isNotNull);
  }

  test_closure() async {
    addTestFile(r'''
main() {
  var items = <int>[1, 2, 3];
  items.forEach((item) {
    item;
  });
  items.forEach((item) {
    item;
  });
}
''');
    await resolveTestFile();

    FunctionDeclaration mainDeclaration = result.unit.declarations[0];
    FunctionElement mainElement = mainDeclaration.element;
    BlockFunctionBody mainBody = mainDeclaration.functionExpression.body;
    List<Statement> mainStatements = mainBody.block.statements;

    VariableDeclarationStatement itemsStatement = mainStatements[0];
    var itemsElement = itemsStatement.variables.variables[0].element;

    // First closure.
    ParameterElement itemElement1;
    {
      ExpressionStatement forStatement = mainStatements[1];
      MethodInvocation forInvocation = forStatement.expression;

      SimpleIdentifier forTarget = forInvocation.target;
      expect(forTarget.staticElement, itemsElement);

      var closureTypeStr = '(int) → Null';
      FunctionExpression closure = forInvocation.argumentList.arguments[0];

      FunctionElementImpl closureElement = closure.element;
      expect(closureElement.enclosingElement, same(mainElement));

      ParameterElement itemElement = closureElement.parameters[0];
      itemElement1 = itemElement;

      expect(closureElement.returnType, typeProvider.nullType);
      expect(closureElement.type.element, same(closureElement));
      expect(closureElement.type.toString(), closureTypeStr);
      expect(closure.staticType, same(closureElement.type));

      List<FormalParameter> closureParameters = closure.parameters.parameters;
      expect(closureParameters, hasLength(1));

      SimpleFormalParameter itemNode = closureParameters[0];
      _assertSimpleParameter(itemNode, itemElement,
          name: 'item',
          offset: 56,
          kind: ParameterKind.REQUIRED,
          type: typeProvider.intType);

      BlockFunctionBody closureBody = closure.body;
      List<Statement> closureStatements = closureBody.block.statements;

      ExpressionStatement itemStatement = closureStatements[0];
      SimpleIdentifier itemIdentifier = itemStatement.expression;
      expect(itemIdentifier.staticElement, itemElement);
      expect(itemIdentifier.staticType, typeProvider.intType);
    }

    // Second closure, same names, different elements.
    {
      ExpressionStatement forStatement = mainStatements[2];
      MethodInvocation forInvocation = forStatement.expression;

      SimpleIdentifier forTarget = forInvocation.target;
      expect(forTarget.staticElement, itemsElement);

      var closureTypeStr = '(int) → Null';
      FunctionExpression closure = forInvocation.argumentList.arguments[0];

      FunctionElementImpl closureElement = closure.element;
      expect(closureElement.enclosingElement, same(mainElement));

      ParameterElement itemElement = closureElement.parameters[0];
      expect(itemElement, isNot(same(itemElement1)));

      expect(closureElement.returnType, typeProvider.nullType);
      expect(closureElement.type.element, same(closureElement));
      expect(closureElement.type.toString(), closureTypeStr);
      expect(closure.staticType, same(closureElement.type));

      List<FormalParameter> closureParameters = closure.parameters.parameters;
      expect(closureParameters, hasLength(1));

      SimpleFormalParameter itemNode = closureParameters[0];
      _assertSimpleParameter(itemNode, itemElement,
          name: 'item',
          offset: 97,
          kind: ParameterKind.REQUIRED,
          type: typeProvider.intType);

      BlockFunctionBody closureBody = closure.body;
      List<Statement> closureStatements = closureBody.block.statements;

      ExpressionStatement itemStatement = closureStatements[0];
      SimpleIdentifier itemIdentifier = itemStatement.expression;
      expect(itemIdentifier.staticElement, itemElement);
      expect(itemIdentifier.staticType, typeProvider.intType);
    }
  }

  test_closure_generic() async {
    addTestFile(r'''
main() {
  foo(<T>() => new List<T>(4));
}

void foo(List<T> Function<T>() createList) {}
''');
    await resolveTestFile();

    var closure = findNode.functionExpression('<T>() =>');
    assertType(closure, '<T>() → List<T>');

    FunctionElementImpl closureElement = closure.element;
    expect(closureElement.enclosingElement, findElement.function('main'));
    expect(closureElement.returnType.toString(), 'List<T>');
    expect(closureElement.parameters, isEmpty);

    var typeParameters = closureElement.typeParameters;
    expect(typeParameters, hasLength(1));

    TypeParameterElement tElement = typeParameters[0];
    expect(tElement.name, 'T');
    expect(tElement.nameOffset, 16);

    var creation = findNode.instanceCreation('new List');
    assertType(creation, 'List<T>');

    var tRef = findNode.simple('T>(4)');
    assertElement(tRef, tElement);
  }

  test_closure_inField() async {
    addTestFile(r'''
class C {
  var v = (() => 42)();
}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;

    ClassDeclaration c = unit.declarations[0];
    FieldDeclaration declaration = c.members[0];
    VariableDeclaration field = declaration.fields.variables[0];
    FunctionElement fieldInitializer = field.element.initializer;

    FunctionExpressionInvocation invocation = field.initializer;
    FunctionExpression closure = invocation.function.unParenthesized;
    FunctionElementImpl closureElement = closure.element;
    expect(closureElement.enclosingElement, same(fieldInitializer));
  }

  test_closure_inTopLevelVariable() async {
    addTestFile(r'''
var v = (() => 42)();
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;

    TopLevelVariableDeclaration declaration = unit.declarations[0];
    VariableDeclaration variable = declaration.variables.variables[0];
    TopLevelVariableElement variableElement = variable.element;
    FunctionElement variableInitializer = variableElement.initializer;

    FunctionExpressionInvocation invocation = variable.initializer;
    FunctionExpression closure = invocation.function.unParenthesized;
    FunctionElementImpl closureElement = closure.element;
    expect(closureElement.enclosingElement, same(variableInitializer));
  }

  test_conditionalExpression() async {
    String content = r'''
void main() {
  true ? 1 : 2.3;
}
''';
    addTestFile(content);
    await resolveTestFile();

    List<Statement> statements = _getMainStatements(result);

    ExpressionStatement statement = statements[0];
    ConditionalExpression expression = statement.expression;
    expect(expression.staticType, typeProvider.numType);
    expect(expression.condition.staticType, typeProvider.boolType);
    expect(expression.thenExpression.staticType, typeProvider.intType);
    expect(expression.elseExpression.staticType, typeProvider.doubleType);
  }

  test_constructor_context() async {
    addTestFile(r'''
class C {
  C(int p) {
    p;
  }
}
''');
    await resolveTestFile();

    ClassDeclaration cNode = result.unit.declarations[0];

    ConstructorDeclaration constructorNode = cNode.members[0];
    ParameterElement pElement = constructorNode.element.parameters[0];

    BlockFunctionBody constructorBody = constructorNode.body;
    ExpressionStatement pStatement = constructorBody.block.statements[0];

    SimpleIdentifier pIdentifier = pStatement.expression;
    expect(pIdentifier.staticElement, same(pElement));
    expect(pIdentifier.staticType, typeProvider.intType);
  }

  test_constructor_initializer_field() async {
    addTestFile(r'''
class C {
  int f;
  C(int p) : f = p {
    f;
  }
}
''');
    await resolveTestFile();

    ClassDeclaration cNode = result.unit.declarations[0];
    ClassElement cElement = cNode.element;
    FieldElement fElement = cElement.getField('f');

    ConstructorDeclaration constructorNode = cNode.members[1];
    ParameterElement pParameterElement = constructorNode.element.parameters[0];

    {
      ConstructorFieldInitializer initializer = constructorNode.initializers[0];
      expect(initializer.fieldName.staticElement, same(fElement));

      SimpleIdentifier expression = initializer.expression;
      expect(expression.staticElement, same(pParameterElement));
    }
  }

  test_constructor_initializer_super() async {
    addTestFile(r'''
class A {
  A(int a);
  A.named(int a, {int b});
}
class B extends A {
  B.one(int p) : super(p + 1);
  B.two(int p) : super.named(p + 1, b: p + 2);
}
''');
    await resolveTestFile();

    ClassDeclaration aNode = result.unit.declarations[0];
    ClassElement aElement = aNode.element;

    ClassDeclaration bNode = result.unit.declarations[1];

    {
      ConstructorDeclaration constructor = bNode.members[0];
      SuperConstructorInvocation initializer = constructor.initializers[0];
      expect(initializer.staticElement, same(aElement.unnamedConstructor));
      expect(initializer.constructorName, isNull);
    }

    {
      var namedConstructor = aElement.getNamedConstructor('named');

      ConstructorDeclaration constructor = bNode.members[1];
      SuperConstructorInvocation initializer = constructor.initializers[0];
      expect(initializer.staticElement, same(namedConstructor));

      var constructorName = initializer.constructorName;
      expect(constructorName.staticElement, same(namedConstructor));
      expect(constructorName.staticType, isNull);

      List<Expression> arguments = initializer.argumentList.arguments;
      _assertArgumentToParameter(arguments[0], namedConstructor.parameters[0]);
      _assertArgumentToParameter(arguments[1], namedConstructor.parameters[1]);
    }
  }

  test_constructor_initializer_this() async {
    addTestFile(r'''
class C {
  C(int a, [int b]);
  C.named(int a, {int b});
  C.one(int p) : this(1, 2);
  C.two(int p) : this.named(3, b: 4);
}
''');
    await resolveTestFile();

    ClassDeclaration cNode = result.unit.declarations[0];
    ClassElement cElement = cNode.element;

    {
      var unnamedConstructor = cElement.constructors[0];

      ConstructorDeclaration constructor = cNode.members[2];
      RedirectingConstructorInvocation initializer =
          constructor.initializers[0];
      expect(initializer.staticElement, same(unnamedConstructor));
      expect(initializer.constructorName, isNull);

      List<Expression> arguments = initializer.argumentList.arguments;
      _assertArgumentToParameter(
          arguments[0], unnamedConstructor.parameters[0]);
      _assertArgumentToParameter(
          arguments[1], unnamedConstructor.parameters[1]);
    }

    {
      var namedConstructor = cElement.constructors[1];

      ConstructorDeclaration constructor = cNode.members[3];
      RedirectingConstructorInvocation initializer =
          constructor.initializers[0];
      expect(initializer.staticElement, same(namedConstructor));

      var constructorName = initializer.constructorName;
      expect(constructorName.staticElement, same(namedConstructor));
      expect(constructorName.staticType, isNull);

      List<Expression> arguments = initializer.argumentList.arguments;
      _assertArgumentToParameter(arguments[0], namedConstructor.parameters[0]);
      _assertArgumentToParameter(arguments[1], namedConstructor.parameters[1]);
    }
  }

  test_constructor_redirected() async {
    addTestFile(r'''
class A implements B {
  A(int a);
  A.named(double a);
}
class B {
  factory B.one(int b) = A;
  factory B.two(double b) = A.named;
}
''');
    await resolveTestFile();
    expect(result.errors, isEmpty);

    ClassDeclaration aNode = result.unit.declarations[0];
    ClassElement aElement = aNode.element;

    ClassDeclaration bNode = result.unit.declarations[1];

    {
      ConstructorElement aUnnamed = aElement.constructors[0];

      ConstructorDeclaration constructor = bNode.members[0];
      ConstructorElement element = constructor.element;
      expect(element.redirectedConstructor, same(aUnnamed));

      var constructorName = constructor.redirectedConstructor;
      expect(constructorName.staticElement, same(aUnnamed));

      TypeName typeName = constructorName.type;
      expect(typeName.type, aElement.type);

      SimpleIdentifier identifier = typeName.name;
      expect(identifier.staticElement, same(aElement));
      expect(identifier.staticType, aElement.type);

      expect(constructorName.name, isNull);
    }

    {
      ConstructorElement aNamed = aElement.constructors[1];

      ConstructorDeclaration constructor = bNode.members[1];
      ConstructorElement element = constructor.element;
      expect(element.redirectedConstructor, same(aNamed));

      var constructorName = constructor.redirectedConstructor;
      expect(constructorName.staticElement, same(aNamed));

      TypeName typeName = constructorName.type;
      expect(typeName.type, aElement.type);

      SimpleIdentifier identifier = typeName.name;
      expect(identifier.staticElement, same(aElement));
      expect(identifier.staticType, aElement.type);

      expect(constructorName.name.staticElement, aNamed);
      expect(constructorName.name.staticType, isNull);
    }
  }

  test_constructor_redirected_generic() async {
    addTestFile(r'''
class A<T> implements B<T> {
  A(int a);
  A.named(double a);
}
class B<U> {
  factory B.one(int b) = A<U>;
  factory B.two(double b) = A<U>.named;
}
''');
    await resolveTestFile();
    expect(result.errors, isEmpty);

    ClassDeclaration aNode = result.unit.declarations[0];
    ClassElement aElement = aNode.element;

    ClassDeclaration bNode = result.unit.declarations[1];
    TypeParameterType uType = bNode.element.typeParameters[0].type;
    InterfaceType auType = aElement.type.instantiate([uType]);

    {
      ConstructorElement expectedElement = aElement.constructors[0];

      ConstructorDeclaration constructor = bNode.members[0];
      ConstructorElement element = constructor.element;

      ConstructorMember actualMember = element.redirectedConstructor;
      expect(actualMember.baseElement, same(expectedElement));
      expect(actualMember.definingType, auType);

      var constructorName = constructor.redirectedConstructor;
      expect(constructorName.staticElement, same(actualMember));

      TypeName typeName = constructorName.type;
      expect(typeName.type, auType);

      SimpleIdentifier identifier = typeName.name;
      expect(identifier.staticElement, same(aElement));
      expect(identifier.staticType, auType);

      expect(constructorName.name, isNull);
    }

    {
      ConstructorElement expectedElement = aElement.constructors[1];

      ConstructorDeclaration constructor = bNode.members[1];
      ConstructorElement element = constructor.element;

      ConstructorMember actualMember = element.redirectedConstructor;
      expect(actualMember.baseElement, same(expectedElement));
      expect(actualMember.definingType, auType);

      var constructorName = constructor.redirectedConstructor;
      expect(constructorName.staticElement, same(actualMember));

      TypeName typeName = constructorName.type;
      expect(typeName.type, auType);

      SimpleIdentifier identifier = typeName.name;
      expect(identifier.staticElement, same(aElement));
      expect(identifier.staticType, auType);

      expect(constructorName.name.staticElement, same(actualMember));
      expect(constructorName.name.staticType, isNull);
    }
  }

  test_enum_toString() async {
    addTestFile(r'''
enum MyEnum { A, B, C }
main(MyEnum e) {
  e.toString();
}
''');
    await resolveTestFile();

    EnumDeclaration enumNode = result.unit.declarations[0];
    ClassElement enumElement = enumNode.element;

    List<Statement> mainStatements = _getMainStatements(result);

    ExpressionStatement statement = mainStatements[0];
    MethodInvocation invocation = statement.expression;
    expect(invocation.staticInvokeType.toString(), '() → String');

    MethodElement methodElement = invocation.methodName.staticElement;
    expect(methodElement.name, 'toString');
    expect(methodElement.enclosingElement, same(enumElement));
  }

  test_error_unresolvedTypeAnnotation() async {
    String content = r'''
main() {
  Foo<int> v = null;
}
''';
    addTestFile(content);
    await resolveTestFile();

    var statements = _getMainStatements(result);

    VariableDeclarationStatement statement = statements[0];

    TypeName typeName = statement.variables.type;
    expect(typeName.type, isUndefinedType);
    if (useCFE) {
      expect(typeName.typeArguments.arguments[0].type, isUndefinedType);
    } else {
      expect(typeName.typeArguments.arguments[0].type, typeProvider.intType);
    }

    VariableDeclaration vNode = statement.variables.variables[0];
    expect(vNode.name.staticType, isUndefinedType);
    expect(vNode.element.type, isUndefinedType);
  }

  test_field_context() async {
    addTestFile(r'''
class C<T> {
  var f = <T>[];
}
''');
    await resolveTestFile();

    ClassDeclaration cNode = result.unit.declarations[0];
    var tElement = cNode.element.typeParameters[0];

    FieldDeclaration fDeclaration = cNode.members[0];
    VariableDeclaration fNode = fDeclaration.fields.variables[0];
    FieldElement fElement = fNode.element;
    expect(fElement.type, typeProvider.listType.instantiate([tElement.type]));
  }

  test_formalParameter_functionTyped() async {
    addTestFile(r'''
class A {
  A(String p(int a));
}
''');
    await resolveTestFile();

    ClassDeclaration clazz = result.unit.declarations[0];
    ConstructorDeclaration constructor = clazz.members[0];
    List<FormalParameter> parameters = constructor.parameters.parameters;

    FunctionTypedFormalParameter p = parameters[0];
    expect(p.element, same(constructor.element.parameters[0]));

    {
      FunctionType type = p.identifier.staticType;
      expect(type.returnType, typeProvider.stringType);

      expect(type.parameters, hasLength(1));
      expect(type.parameters[0].type, typeProvider.intType);
    }

    _assertTypeNameSimple(p.returnType, typeProvider.stringType);

    {
      SimpleFormalParameter a = p.parameters.parameters[0];
      _assertTypeNameSimple(a.type, typeProvider.intType);
      expect(a.identifier.staticType, typeProvider.intType);
    }
  }

  test_formalParameter_functionTyped_fieldFormal_typed() async {
    // TODO(scheglov) Add "untyped" version with precise type in field.
    addTestFile(r'''
class A {
  Function f;
  A(String this.f(int a));
}
''');
    await resolveTestFile();

    ClassDeclaration clazz = result.unit.declarations[0];

    FieldDeclaration fDeclaration = clazz.members[0];
    VariableDeclaration fNode = fDeclaration.fields.variables[0];
    FieldElement fElement = fNode.element;

    ConstructorDeclaration constructor = clazz.members[1];

    FieldFormalParameterElement pElement = constructor.element.parameters[0];
    expect(pElement.field, same(fElement));

    List<FormalParameter> parameters = constructor.parameters.parameters;
    FieldFormalParameter p = parameters[0];
    expect(p.element, same(pElement));

    expect(p.identifier.staticElement, same(pElement));
    expect(p.identifier.staticType.toString(), '(int) → String');

    {
      FunctionType type = p.identifier.staticType;
      expect(type.returnType, typeProvider.stringType);

      expect(type.parameters, hasLength(1));
      expect(type.parameters[0].type, typeProvider.intType);
    }

    _assertTypeNameSimple(p.type, typeProvider.stringType);

    {
      SimpleFormalParameter a = p.parameters.parameters[0];
      _assertTypeNameSimple(a.type, typeProvider.intType);
      expect(a.identifier.staticType, typeProvider.intType);
    }
  }

  test_formalParameter_simple_fieldFormal() async {
    addTestFile(r'''
class A {
  int f;
  A(this.f);
}
''');
    await resolveTestFile();

    ClassDeclaration clazz = result.unit.declarations[0];

    FieldDeclaration fDeclaration = clazz.members[0];
    VariableDeclaration fNode = fDeclaration.fields.variables[0];
    FieldElement fElement = fNode.element;

    ConstructorDeclaration constructor = clazz.members[1];
    List<FormalParameter> parameters = constructor.parameters.parameters;

    FieldFormalParameterElement parameterElement =
        constructor.element.parameters[0];
    expect(parameterElement.field, same(fElement));

    FieldFormalParameter parameterNode = parameters[0];
    expect(parameterNode.type, isNull);
    expect(parameterNode.element, same(parameterElement));

    expect(parameterNode.identifier.staticElement, same(parameterElement));
    expect(parameterNode.identifier.staticType, typeProvider.intType);
  }

  test_formalParameter_simple_fieldFormal_typed() async {
    addTestFile(r'''
class A {
  int f;
  A(int this.f);
}
''');
    await resolveTestFile();

    ClassDeclaration clazz = result.unit.declarations[0];

    FieldDeclaration fDeclaration = clazz.members[0];
    VariableDeclaration fNode = fDeclaration.fields.variables[0];
    FieldElement fElement = fNode.element;

    ConstructorDeclaration constructor = clazz.members[1];
    List<FormalParameter> parameters = constructor.parameters.parameters;

    FieldFormalParameterElement parameterElement =
        constructor.element.parameters[0];
    expect(parameterElement.field, same(fElement));

    FieldFormalParameter parameterNode = parameters[0];
    _assertTypeNameSimple(parameterNode.type, typeProvider.intType);
    expect(parameterNode.element, same(parameterElement));

    expect(parameterNode.identifier.staticElement, same(parameterElement));
    expect(parameterNode.identifier.staticType, typeProvider.intType);
  }

  test_forwardingStub_class() async {
    addTestFile(r'''
class A<T> {
  void m(T t) {}
}
class B extends A<int> {}
main(B b) {
  b.m(1);
}
''');
    await resolveTestFile();

    ClassDeclaration aNode = result.unit.declarations[0];
    ClassElement eElement = aNode.element;
    MethodElement mElement = eElement.getMethod('m');

    List<Statement> mainStatements = _getMainStatements(result);

    ExpressionStatement statement = mainStatements[0];
    MethodInvocation invocation = statement.expression;
    expect(invocation.staticInvokeType.toString(), '(int) → void');
    if (useCFE) {
      expect(invocation.methodName.staticElement, same(mElement));
    }
  }

  test_functionExpressionInvocation() async {
    addTestFile(r'''
typedef Foo<S> = S Function<T>(T x);
void main(f) {
  (f as Foo<int>)<String>('hello');
}
''');
    await resolveTestFile();

    List<Statement> statements = _getMainStatements(result);

    ExpressionStatement statement = statements[0];
    FunctionExpressionInvocation invocation = statement.expression;

    expect(invocation.staticElement, isNull);
    expect(invocation.staticInvokeType.toString(), '(String) → int');
    expect(invocation.staticType, typeProvider.intType);

    List<TypeAnnotation> typeArguments = invocation.typeArguments.arguments;
    expect(typeArguments, hasLength(1));
    _assertTypeNameSimple(typeArguments[0], typeProvider.stringType);
  }

  test_indexExpression() async {
    String content = r'''
main() {
  var items = <int>[1, 2, 3];
  items[0];
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;

    var typeProvider = unit.element.context.typeProvider;
    InterfaceType intType = typeProvider.intType;
    InterfaceType listType = typeProvider.listType;
    InterfaceType listIntType = listType.instantiate([intType]);

    List<Statement> mainStatements = _getMainStatements(result);

    VariableElement itemsElement;
    {
      VariableDeclarationStatement statement = mainStatements[0];
      VariableDeclaration itemsNode = statement.variables.variables[0];
      itemsElement = itemsNode.element;
      expect(itemsElement.type, listIntType);
    }

    ExpressionStatement statement = mainStatements[1];
    IndexExpression indexExpression = statement.expression;
    expect(indexExpression.staticType, intType);

    MethodMember actualElement = indexExpression.staticElement;
    MethodMember expectedElement = listIntType.getMethod('[]');
    expect(actualElement.name, '[]');
    expect(actualElement.baseElement, same(expectedElement.baseElement));
    expect(actualElement.returnType, intType);
    expect(actualElement.parameters[0].type, intType);
  }

  test_indexExpression_cascade_assign() async {
    addTestFile(r'''
main() {
  <int, int>{}..[1] = 10;
}
''');
    await resolveTestFile();

    var cascade = findNode.cascade('<int, int>');
    assertType(cascade, 'Map<int, int>');

    MapLiteral map = cascade.target;
    assertType(map, 'Map<int, int>');
    assertTypeArguments(map.typeArguments, [intType, intType]);

    AssignmentExpression assignment = cascade.cascadeSections[0];
    assertElementNull(assignment);
    assertType(assignment, 'int');

    IndexExpression indexed = assignment.leftHandSide;
    assertMember(indexed, 'Map<int, int>', mapElement.getMethod('[]='));
    assertType(indexed, 'int');
  }

  test_instanceCreation_factory() async {
    String content = r'''
class C {
  factory C() => null;
  factory C.named() => null;
}
var a = new C();
var b = new C.named();
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;

    ClassDeclaration cNode = unit.declarations[0];
    ClassElement cElement = cNode.element;
    ConstructorElement defaultConstructor = cElement.constructors[0];
    ConstructorElement namedConstructor = cElement.constructors[1];

    {
      TopLevelVariableDeclaration aDeclaration = unit.declarations[1];
      VariableDeclaration aNode = aDeclaration.variables.variables[0];
      InstanceCreationExpression value = aNode.initializer;
      expect(value.staticElement, defaultConstructor);
      expect(value.staticType, cElement.type);

      TypeName typeName = value.constructorName.type;
      expect(typeName.typeArguments, isNull);

      Identifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, cElement);
      expect(typeIdentifier.staticType, cElement.type);

      expect(value.constructorName.name, isNull);
    }

    {
      TopLevelVariableDeclaration bDeclaration = unit.declarations[2];
      VariableDeclaration bNode = bDeclaration.variables.variables[0];
      InstanceCreationExpression value = bNode.initializer;
      expect(value.staticElement, namedConstructor);
      expect(value.staticType, cElement.type);

      TypeName typeName = value.constructorName.type;
      expect(typeName.typeArguments, isNull);

      SimpleIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, cElement);
      expect(typeIdentifier.staticType, cElement.type);

      SimpleIdentifier constructorName = value.constructorName.name;
      expect(constructorName.staticElement, namedConstructor);
      expect(constructorName.staticType, isNull);
    }
  }

  test_instanceCreation_namedArgument() async {
    addTestFile(r'''
class X {
  X(int a, {bool b, double c});
}
var v = new X(1, b: true, c: 3.0);
''');

    await resolveTestFile();
    CompilationUnit unit = result.unit;

    ClassDeclaration xNode = unit.declarations[0];
    ClassElement xElement = xNode.element;
    ConstructorElement constructorElement = xElement.constructors[0];

    TopLevelVariableDeclaration vDeclaration = unit.declarations[1];
    VariableDeclaration vNode = vDeclaration.variables.variables[0];

    InstanceCreationExpression creation = vNode.initializer;
    List<Expression> arguments = creation.argumentList.arguments;
    expect(creation.staticElement, constructorElement);
    expect(creation.staticType, xElement.type);

    TypeName typeName = creation.constructorName.type;
    expect(typeName.typeArguments, isNull);

    Identifier typeIdentifier = typeName.name;
    expect(typeIdentifier.staticElement, xElement);
    expect(typeIdentifier.staticType, xElement.type);

    expect(creation.constructorName.name, isNull);

    _assertArgumentToParameter(arguments[0], constructorElement.parameters[0]);
    _assertArgumentToParameter(arguments[1], constructorElement.parameters[1]);
    _assertArgumentToParameter(arguments[2], constructorElement.parameters[2]);
  }

  test_instanceCreation_noTypeArguments() async {
    String content = r'''
class C {
  C(int p);
  C.named(int p);
}
var a = new C(1);
var b = new C.named(2);
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;

    ClassDeclaration cNode = unit.declarations[0];
    ClassElement cElement = cNode.element;
    ConstructorElement defaultConstructor = cElement.constructors[0];
    ConstructorElement namedConstructor = cElement.constructors[1];

    {
      TopLevelVariableDeclaration aDeclaration = unit.declarations[1];
      VariableDeclaration aNode = aDeclaration.variables.variables[0];
      InstanceCreationExpression value = aNode.initializer;
      expect(value.staticElement, defaultConstructor);
      expect(value.staticType, cElement.type);

      TypeName typeName = value.constructorName.type;
      expect(typeName.typeArguments, isNull);

      Identifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, cElement);
      expect(typeIdentifier.staticType, cElement.type);

      expect(value.constructorName.name, isNull);

      Expression argument = value.argumentList.arguments[0];
      _assertArgumentToParameter(argument, defaultConstructor.parameters[0]);
    }

    {
      TopLevelVariableDeclaration bDeclaration = unit.declarations[2];
      VariableDeclaration bNode = bDeclaration.variables.variables[0];
      InstanceCreationExpression value = bNode.initializer;
      expect(value.staticElement, namedConstructor);
      expect(value.staticType, cElement.type);

      TypeName typeName = value.constructorName.type;
      expect(typeName.typeArguments, isNull);

      SimpleIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, cElement);
      expect(typeIdentifier.staticType, cElement.type);

      SimpleIdentifier constructorName = value.constructorName.name;
      expect(constructorName.staticElement, namedConstructor);
      expect(constructorName.staticType, isNull);

      Expression argument = value.argumentList.arguments[0];
      _assertArgumentToParameter(argument, namedConstructor.parameters[0]);
    }
  }

  test_instanceCreation_prefixed() async {
    var a = _p('/test/lib/a.dart');
    provider.newFile(a, r'''
class C<T> {
  C(T p);
  C.named(T p);
}
''');
    addTestFile(r'''
import 'a.dart' as p;
main() {
  new p.C(0);
  new p.C.named(1.2);
  new p.C<bool>.named(false);
}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ImportElement aImport = unit.element.library.imports[0];
    LibraryElement aLibrary = aImport.importedLibrary;

    ClassElement cElement = aLibrary.getType('C');
    ConstructorElement defaultConstructor = cElement.constructors[0];
    ConstructorElement namedConstructor = cElement.constructors[1];
    InterfaceType cType = cElement.type;
    var cTypeDynamic = cType.instantiate([DynamicTypeImpl.instance]);

    var statements = _getMainStatements(result);
    {
      var cTypeInt = cType.instantiate([typeProvider.intType]);

      ExpressionStatement statement = statements[0];
      InstanceCreationExpression creation = statement.expression;
      expect(creation.staticElement, defaultConstructor);
      expect(creation.staticType, cTypeInt);

      TypeName typeName = creation.constructorName.type;
      expect(typeName.typeArguments, isNull);

      PrefixedIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, same(cElement));
      if (useCFE) {
        expect(typeIdentifier.staticType, cTypeInt);
      } else {
        expect(typeIdentifier.staticType, cTypeDynamic);
      }

      SimpleIdentifier typePrefix = typeIdentifier.prefix;
      expect(typePrefix.name, 'p');
      expect(typePrefix.staticElement, same(aImport.prefix));
      expect(typePrefix.staticType, isNull);

      expect(typeIdentifier.identifier.staticElement, same(cElement));

      expect(creation.constructorName.name, isNull);
    }

    {
      var cTypeDouble = cType.instantiate([typeProvider.doubleType]);

      ExpressionStatement statement = statements[1];
      InstanceCreationExpression creation = statement.expression;
      expect(creation.staticElement, namedConstructor);
      expect(creation.staticType, cTypeDouble);

      TypeName typeName = creation.constructorName.type;
      expect(typeName.typeArguments, isNull);

      PrefixedIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, cElement);
      if (useCFE) {
        expect(typeIdentifier.staticType, cTypeDouble);
      } else {
        expect(typeIdentifier.staticType, cTypeDynamic);
      }

      SimpleIdentifier typePrefix = typeIdentifier.prefix;
      expect(typePrefix.name, 'p');
      expect(typePrefix.staticElement, same(aImport.prefix));
      expect(typePrefix.staticType, isNull);

      expect(typeIdentifier.identifier.staticElement, same(cElement));

      SimpleIdentifier constructorName = creation.constructorName.name;
      expect(constructorName.staticElement, namedConstructor);
      expect(constructorName.staticType, isNull);
    }

    {
      var cTypeBool = cType.instantiate([typeProvider.boolType]);

      ExpressionStatement statement = statements[2];
      InstanceCreationExpression creation = statement.expression;
      expect(creation.staticElement, namedConstructor);
      expect(creation.staticType, cTypeBool);

      TypeName typeName = creation.constructorName.type;
      expect(typeName.typeArguments.arguments, hasLength(1));
      _assertTypeNameSimple(
          typeName.typeArguments.arguments[0], typeProvider.boolType);

      PrefixedIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, cElement);
      expect(typeIdentifier.staticType, cTypeBool);

      SimpleIdentifier typePrefix = typeIdentifier.prefix;
      expect(typePrefix.name, 'p');
      expect(typePrefix.staticElement, same(aImport.prefix));
      expect(typePrefix.staticType, isNull);

      expect(typeIdentifier.identifier.staticElement, same(cElement));

      SimpleIdentifier constructorName = creation.constructorName.name;
      expect(constructorName.staticElement, namedConstructor);
      expect(constructorName.staticType, isNull);
    }
  }

  test_instanceCreation_unprefixed() async {
    addTestFile(r'''
main() {
  new C(0);
  new C<bool>(false);
  new C.named(1.2);
  new C<bool>.named(false);
}

class C<T> {
  C(T p);
  C.named(T p);
}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    CompilationUnitElement unitElement = unit.element;
    var typeProvider = unitElement.context.typeProvider;

    ClassElement cElement = unitElement.getType('C');
    ConstructorElement defaultConstructor = cElement.constructors[0];
    ConstructorElement namedConstructor = cElement.constructors[1];
    InterfaceType cType = cElement.type;
    var cTypeDynamic = cType.instantiate([DynamicTypeImpl.instance]);

    var statements = _getMainStatements(result);
    {
      var cTypeInt = cType.instantiate([typeProvider.intType]);

      ExpressionStatement statement = statements[0];
      InstanceCreationExpression creation = statement.expression;
      expect(creation.staticElement, defaultConstructor);
      expect(creation.staticType, cTypeInt);

      TypeName typeName = creation.constructorName.type;
      expect(typeName.typeArguments, isNull);

      SimpleIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, same(cElement));
      if (useCFE) {
        expect(typeIdentifier.staticType, cTypeInt);
      } else {
        expect(typeIdentifier.staticType, cTypeDynamic);
      }

      expect(creation.constructorName.name, isNull);
    }

    {
      var cTypeBool = cType.instantiate([typeProvider.boolType]);

      ExpressionStatement statement = statements[1];
      InstanceCreationExpression creation = statement.expression;
      expect(creation.staticElement, defaultConstructor);
      expect(creation.staticType, cTypeBool);

      TypeName typeName = creation.constructorName.type;
      expect(typeName.typeArguments.arguments, hasLength(1));
      _assertTypeNameSimple(
          typeName.typeArguments.arguments[0], typeProvider.boolType);

      SimpleIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, same(cElement));
      expect(typeIdentifier.staticType, cTypeBool);

      expect(creation.constructorName.name, isNull);
    }

    {
      var cTypeDouble = cType.instantiate([typeProvider.doubleType]);

      ExpressionStatement statement = statements[2];
      InstanceCreationExpression creation = statement.expression;
      expect(creation.staticElement, namedConstructor);
      expect(creation.staticType, cTypeDouble);

      TypeName typeName = creation.constructorName.type;
      expect(typeName.typeArguments, isNull);

      SimpleIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, cElement);
      if (useCFE) {
        expect(typeIdentifier.staticType, cTypeDouble);
      } else {
        expect(typeIdentifier.staticType, cTypeDynamic);
      }

      expect(typeIdentifier.staticElement, same(cElement));

      SimpleIdentifier constructorName = creation.constructorName.name;
      expect(constructorName.staticElement, namedConstructor);
      expect(constructorName.staticType, isNull);
    }

    {
      var cTypeBool = cType.instantiate([typeProvider.boolType]);

      ExpressionStatement statement = statements[3];
      InstanceCreationExpression creation = statement.expression;
      expect(creation.staticElement, namedConstructor);
      expect(creation.staticType, cTypeBool);

      TypeName typeName = creation.constructorName.type;
      expect(typeName.typeArguments.arguments, hasLength(1));
      _assertTypeNameSimple(
          typeName.typeArguments.arguments[0], typeProvider.boolType);

      SimpleIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, cElement);
      expect(typeIdentifier.staticType, cTypeBool);

      SimpleIdentifier constructorName = creation.constructorName.name;
      expect(constructorName.staticElement, namedConstructor);
      expect(constructorName.staticType, isNull);
    }
  }

  test_instanceCreation_withTypeArguments() async {
    String content = r'''
class C<K, V> {
  C(K k, V v);
  C.named(K k, V v);
}
var a = new C<int, double>(1, 2.3);
var b = new C<num, String>.named(4, 'five');
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cNode = unit.declarations[0];
    ClassElement cElement = cNode.element;
    ConstructorElement defaultConstructor = cElement.constructors[0];
    ConstructorElement namedConstructor = cElement.constructors[1];

    {
      TopLevelVariableDeclaration aDeclaration = unit.declarations[1];
      VariableDeclaration aNode = aDeclaration.variables.variables[0];

      InstanceCreationExpression value = aNode.initializer;
      InterfaceType instantiatedType = cElement.type
          .instantiate([typeProvider.intType, typeProvider.doubleType]);

      expect(value.staticElement, defaultConstructor);
      expect(value.staticType, instantiatedType);

      TypeName typeName = value.constructorName.type;

      Identifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, cElement);
      expect(typeIdentifier.staticType, instantiatedType);

      TypeName typeArgument1 = typeName.typeArguments.arguments[0];
      expect(typeArgument1.type, typeProvider.intType);
      expect(typeArgument1.name.staticType, typeProvider.intType);
      expect(typeArgument1.name.staticElement, typeProvider.intType.element);

      TypeName typeArgument2 = typeName.typeArguments.arguments[1];
      expect(typeArgument2.type, typeProvider.doubleType);
      expect(typeArgument2.name.staticType, typeProvider.doubleType);
      expect(typeArgument2.name.staticElement, typeProvider.doubleType.element);

      expect(value.constructorName.name, isNull);

      Expression argument = value.argumentList.arguments[0];
      _assertArgumentToParameter(argument, defaultConstructor.parameters[0]);
    }

    {
      TopLevelVariableDeclaration bDeclaration = unit.declarations[2];
      VariableDeclaration bNode = bDeclaration.variables.variables[0];

      InstanceCreationExpression value = bNode.initializer;
      InterfaceType instantiatedType = cElement.type
          .instantiate([typeProvider.numType, typeProvider.stringType]);

      expect(value.staticElement, namedConstructor);
      expect(value.staticType, instantiatedType);

      TypeName typeName = value.constructorName.type;

      SimpleIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, cElement);
      expect(typeIdentifier.staticType, instantiatedType);

      TypeName typeArgument1 = typeName.typeArguments.arguments[0];
      expect(typeArgument1.type, typeProvider.numType);
      expect(typeArgument1.name.staticType, typeProvider.numType);
      expect(typeArgument1.name.staticElement, typeProvider.numType.element);

      TypeName typeArgument2 = typeName.typeArguments.arguments[1];
      expect(typeArgument2.type, typeProvider.stringType);
      expect(typeArgument2.name.staticType, typeProvider.stringType);
      expect(typeArgument2.name.staticElement, typeProvider.stringType.element);

      SimpleIdentifier constructorName = value.constructorName.name;
      expect(constructorName.staticElement, namedConstructor);
      expect(constructorName.staticType, isNull);

      Expression argument = value.argumentList.arguments[0];
      _assertArgumentToParameter(argument, namedConstructor.parameters[0]);
    }
  }

  test_invalid_assignment_types_local() async {
    addTestFile(r'''
int a;
bool b;
main() {
  a = b;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var assignment = findNode.assignment('a = b');
    assertElementNull(assignment);
    assertType(assignment, 'bool');

    SimpleIdentifier aRef = assignment.leftHandSide;
    assertElement(aRef, findElement.topVar('a').setter);
    assertType(aRef, 'int');

    SimpleIdentifier bRef = assignment.rightHandSide;
    assertElement(bRef, findElement.topVar('b').getter);
    assertType(bRef, 'bool');
  }

  test_invalid_assignment_types_top() async {
    addTestFile(r'''
int a = 0;
bool b = a;
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var bDeclaration = findNode.variableDeclaration('b =');
    TopLevelVariableElement bElement = bDeclaration.element;
    assertElement(bDeclaration.name, bElement);
    assertType(bDeclaration.name, 'bool');
    expect(bElement.type.toString(), 'bool');

    SimpleIdentifier aRef = bDeclaration.initializer;
    assertElement(aRef, findElement.topGet('a'));
    assertType(aRef, 'int');
  }

  test_invalid_assignment_types_top_const() async {
    addTestFile(r'''
const int a = 0;
const bool b = a;
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var bDeclaration = findNode.variableDeclaration('b =');
    TopLevelVariableElement bElement = bDeclaration.element;
    assertElement(bDeclaration.name, bElement);
    assertType(bDeclaration.name, 'bool');
    expect(bElement.type.toString(), 'bool');

    SimpleIdentifier aRef = bDeclaration.initializer;
    assertElement(aRef, findElement.topGet('a'));
    assertType(aRef, 'int');
  }

  test_invalid_instanceCreation_abstract() async {
    addTestFile(r'''
abstract class C<T> {
  C(T a);
  C.named(T a);
  C.named2();
}
var a = 0;
var b = true;
main() {
  new C(a);
  new C.named(b);
  new C<double>.named2();
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var c = findElement.class_('C');

    {
      var creation = findNode.instanceCreation('new C(a)');
      assertType(creation, 'C<int>');

      ConstructorName constructorName = creation.constructorName;
      expect(constructorName.name, isNull);

      TypeName type = constructorName.type;
      expect(type.typeArguments, isNull);
      assertElement(type.name, c);
      assertType(type.name, useCFE ? 'C<int>' : 'C<dynamic>');

      SimpleIdentifier aRef = creation.argumentList.arguments[0];
      assertElement(aRef, findElement.topGet('a'));
      assertType(aRef, 'int');
    }

    {
      var creation = findNode.instanceCreation('new C.named(b)');
      assertType(creation, 'C<bool>');

      ConstructorName constructorName = creation.constructorName;
      expect(constructorName.name.name, 'named');

      TypeName type = constructorName.type;
      expect(type.typeArguments, isNull);
      assertElement(type.name, c);
      assertType(type.name, useCFE ? 'C<bool>' : 'C<dynamic>');

      SimpleIdentifier bRef = creation.argumentList.arguments[0];
      assertElement(bRef, findElement.topGet('b'));
      assertType(bRef, 'bool');
    }

    {
      var creation = findNode.instanceCreation('new C<double>.named2()');
      assertType(creation, 'C<double>');

      ConstructorName constructorName = creation.constructorName;
      expect(constructorName.name.name, 'named2');

      TypeName type = constructorName.type;
      assertTypeArguments(type.typeArguments, [doubleType]);
      assertElement(type.name, c);
      assertType(type.name, 'C<double>');
    }
  }

  test_invalid_methodInvocation_simpleIdentifier() async {
    addTestFile(r'''
int foo = 0;
main() {
  foo(1);
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    TopLevelVariableElement foo = _getTopLevelVariable(result, 'foo');

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    MethodInvocation invocation = statement.expression;
    expect(invocation.staticType, isDynamicType);
    if (useCFE) {
      // TODO(scheglov) https://github.com/dart-lang/sdk/issues/33682
      expect(invocation.staticInvokeType.toString(), '() → dynamic');
    } else {
      expect(invocation.staticInvokeType, typeProvider.intType);
    }

    SimpleIdentifier name = invocation.methodName;
    expect(name.staticElement, same(foo.getter));
    expect(name.staticType, typeProvider.intType);
  }

  test_isExpression() async {
    String content = r'''
void main() {
  var v = 42;
  v is num;
}
''';
    addTestFile(content);

    await resolveTestFile();
    expect(result.path, testFile);
    expect(result.errors, isEmpty);

    NodeList<Statement> statements = _getMainStatements(result);

    // var v = 42;
    VariableElement vElement;
    {
      VariableDeclarationStatement statement = statements[0];
      vElement = statement.variables.variables[0].name.staticElement;
    }

    // v is num;
    {
      ExpressionStatement statement = statements[1];
      IsExpression isExpression = statement.expression;
      expect(isExpression.notOperator, isNull);
      expect(isExpression.staticType, typeProvider.boolType);

      SimpleIdentifier target = isExpression.expression;
      expect(target.staticElement, vElement);
      expect(target.staticType, typeProvider.intType);

      TypeName numName = isExpression.type;
      expect(numName.name.staticElement, typeProvider.numType.element);
      expect(numName.name.staticType, typeProvider.numType);
    }
  }

  test_isExpression_not() async {
    String content = r'''
void main() {
  var v = 42;
  v is! num;
}
''';
    addTestFile(content);

    await resolveTestFile();
    expect(result.path, testFile);
    expect(result.errors, isEmpty);

    NodeList<Statement> statements = _getMainStatements(result);

    // var v = 42;
    VariableElement vElement;
    {
      VariableDeclarationStatement statement = statements[0];
      vElement = statement.variables.variables[0].name.staticElement;
    }

    // v is! num;
    {
      ExpressionStatement statement = statements[1];
      IsExpression isExpression = statement.expression;
      expect(isExpression.notOperator, isNotNull);
      expect(isExpression.staticType, typeProvider.boolType);

      SimpleIdentifier target = isExpression.expression;
      expect(target.staticElement, vElement);
      expect(target.staticType, typeProvider.intType);

      TypeName numName = isExpression.type;
      expect(numName.name.staticElement, typeProvider.numType.element);
      expect(numName.name.staticType, typeProvider.numType);
    }
  }

  test_label_while() async {
    addTestFile(r'''
main() {
  myLabel:
  while (true) {
    continue myLabel;
    break myLabel;
  }
}
''');
    await resolveTestFile();
    List<Statement> statements = _getMainStatements(result);

    LabeledStatement statement = statements[0];

    Label label = statement.labels.single;
    LabelElement labelElement = label.label.staticElement;

    WhileStatement whileStatement = statement.statement;
    Block whileBlock = whileStatement.body;

    ContinueStatement continueStatement = whileBlock.statements[0];
    expect(continueStatement.label.staticElement, same(labelElement));
    expect(continueStatement.label.staticType, isNull);

    BreakStatement breakStatement = whileBlock.statements[1];
    expect(breakStatement.label.staticElement, same(labelElement));
    expect(breakStatement.label.staticType, isNull);
  }

  test_local_function() async {
    addTestFile(r'''
void main() {
  double f(int a, String b) {}
  var v = f(1, '2');
}
''');
    String fTypeString = '(int, String) → double';

    await resolveTestFile();
    List<Statement> mainStatements = _getMainStatements(result);

    InterfaceType doubleType = typeProvider.doubleType;

    FunctionDeclarationStatement fStatement = mainStatements[0];
    FunctionDeclaration fNode = fStatement.functionDeclaration;
    FunctionExpression fExpression = fNode.functionExpression;
    FunctionElement fElement = fNode.element;
    expect(fElement, isNotNull);
    expect(fElement.type.toString(), fTypeString);

    expect(fNode.name.staticElement, same(fElement));
    expect(fNode.name.staticType, fElement.type);

    TypeName fReturnTypeNode = fNode.returnType;
    expect(fReturnTypeNode.name.staticElement, same(doubleType.element));
    expect(fReturnTypeNode.type, doubleType);

    expect(fExpression.element, same(fElement));

    {
      List<ParameterElement> elements = fElement.parameters;
      expect(elements, hasLength(2));

      List<FormalParameter> nodes = fExpression.parameters.parameters;
      expect(nodes, hasLength(2));

      _assertSimpleParameter(nodes[0], elements[0],
          name: 'a',
          offset: 29,
          kind: ParameterKind.REQUIRED,
          type: typeProvider.intType);

      _assertSimpleParameter(nodes[1], elements[1],
          name: 'b',
          offset: 39,
          kind: ParameterKind.REQUIRED,
          type: typeProvider.stringType);
    }

    VariableDeclarationStatement vStatement = mainStatements[1];
    VariableDeclaration vDeclaration = vStatement.variables.variables[0];
    expect(vDeclaration.element.type, same(doubleType));

    MethodInvocation fInvocation = vDeclaration.initializer;
    expect(fInvocation.methodName.staticElement, same(fElement));
    expect(fInvocation.methodName.staticType.toString(), fTypeString);
    expect(fInvocation.staticType, same(doubleType));
    expect(fInvocation.staticInvokeType.toString(), fTypeString);
  }

  test_local_function_generic() async {
    addTestFile(r'''
void main() {
  T f<T, U>(T a, U b) {
    a;
    b;
  }
  var v = f(1, '2');
}
''');
    await resolveTestFile();

    List<Statement> mainStatements = _getMainStatements(result);

    FunctionDeclarationStatement fStatement = mainStatements[0];
    FunctionDeclaration fNode = fStatement.functionDeclaration;
    FunctionExpression fExpression = fNode.functionExpression;
    FunctionElement fElement = fNode.element;

    TypeParameterElement tElement = fElement.typeParameters[0];
    TypeParameterElement uElement = fElement.typeParameters[1];

    {
      var fTypeParameters = fExpression.typeParameters.typeParameters;
      expect(fTypeParameters, hasLength(2));

      TypeParameter tNode = fTypeParameters[0];
      expect(tNode.element, same(tElement));
      expect(tNode.name.staticElement, same(tElement));
      expect(tNode.name.staticType, typeProvider.typeType);

      TypeParameter uNode = fTypeParameters[1];
      expect(uNode.element, same(uElement));
      expect(uNode.name.staticElement, same(uElement));
      expect(uNode.name.staticType, typeProvider.typeType);
    }

    expect(fElement, isNotNull);
    expect(fElement.type.toString(), '<T,U>(T, U) → T');

    expect(fNode.name.staticElement, same(fElement));
    expect(fNode.name.staticType, fElement.type);

    TypeName fReturnTypeNode = fNode.returnType;
    expect(fReturnTypeNode.name.staticElement, same(tElement));
    expect(fReturnTypeNode.type, tElement.type);

    expect(fExpression.element, same(fElement));

    {
      List<ParameterElement> parameters = fElement.parameters;
      expect(parameters, hasLength(2));

      List<FormalParameter> nodes = fExpression.parameters.parameters;
      expect(nodes, hasLength(2));

      _assertSimpleParameter(nodes[0], parameters[0],
          name: 'a',
          offset: 28,
          kind: ParameterKind.REQUIRED,
          type: tElement.type);

      _assertSimpleParameter(nodes[1], parameters[1],
          name: 'b',
          offset: 33,
          kind: ParameterKind.REQUIRED,
          type: uElement.type);

      var aRef = findNode.simple('a;');
      assertElement(aRef, parameters[0]);
      assertType(aRef, 'T');

      var bRef = findNode.simple('b;');
      assertElement(bRef, parameters[1]);
      assertType(bRef, 'U');
    }

    VariableDeclarationStatement vStatement = mainStatements[1];
    VariableDeclaration vDeclaration = vStatement.variables.variables[0];
    expect(vDeclaration.element.type, typeProvider.intType);

    MethodInvocation fInvocation = vDeclaration.initializer;
    expect(fInvocation.methodName.staticElement, same(fElement));
    expect(fInvocation.staticType, typeProvider.intType);
    // TODO(scheglov) We don't support invoke types well.
//    if (useCFE) {
//      String fInstantiatedType = '(int, String) → int';
//      expect(fInvocation.methodName.staticType.toString(), fInstantiatedType);
//      expect(fInvocation.staticInvokeType.toString(), fInstantiatedType);
//    }
  }

  test_local_function_generic_f_bounded() async {
    addTestFile('''
void main() {
  void F<T extends U, U, V extends U>(T x, U y, V z) {}
}
''');
    await resolveTestFile();
    List<Statement> mainStatements = _getMainStatements(result);

    FunctionDeclarationStatement fStatement = mainStatements[0];
    FunctionDeclaration fNode = fStatement.functionDeclaration;
    FunctionElement fElement = fNode.element;

    expect(fElement.type.toString(),
        '<T extends U,U,V extends U>(T, U, V) → void');
    var tElement = fElement.typeParameters[0];
    var uElement = fElement.typeParameters[1];
    var vElement = fElement.typeParameters[2];
    expect((tElement.bound as TypeParameterType).element, same(uElement));
    expect((vElement.bound as TypeParameterType).element, same(uElement));
  }

  test_local_function_generic_with_named_parameter() async {
    addTestFile('''
void main() {
  void F<T>({T x}) {}
}
''');
    await resolveTestFile();
    List<Statement> mainStatements = _getMainStatements(result);

    FunctionDeclarationStatement fStatement = mainStatements[0];
    FunctionDeclaration fNode = fStatement.functionDeclaration;
    FunctionElement fElement = fNode.element;

    expect(fElement.type.toString(), '<T>({x: T}) → void');
    var tElement = fElement.typeParameters[0];
    expect(fElement.type.typeFormals[0], same(tElement));
    expect((fElement.type.parameters[0].type as TypeParameterType).element,
        same(tElement));
  }

  test_local_function_generic_with_optional_parameter() async {
    addTestFile('''
void main() {
  void F<T>([T x]) {}
}
''');
    await resolveTestFile();
    List<Statement> mainStatements = _getMainStatements(result);

    FunctionDeclarationStatement fStatement = mainStatements[0];
    FunctionDeclaration fNode = fStatement.functionDeclaration;
    FunctionElement fElement = fNode.element;

    expect(fElement.type.toString(), '<T>([T]) → void');
    var tElement = fElement.typeParameters[0];
    expect(fElement.type.typeFormals[0], same(tElement));
    expect((fElement.type.parameters[0].type as TypeParameterType).element,
        same(tElement));
  }

  test_local_function_namedParameters() async {
    addTestFile(r'''
void main() {
  double f(int a, {String b, bool c: false}) {}
  f(1, b: '2', c: true);
}
''');
    String fTypeString = '(int, {b: String, c: bool}) → double';

    await resolveTestFile();
    List<Statement> mainStatements = _getMainStatements(result);

    InterfaceType doubleType = typeProvider.doubleType;

    FunctionDeclarationStatement fStatement = mainStatements[0];
    FunctionDeclaration fNode = fStatement.functionDeclaration;
    FunctionExpression fExpression = fNode.functionExpression;
    FunctionElement fElement = fNode.element;
    expect(fElement, isNotNull);
    expect(fElement.type.toString(), fTypeString);

    expect(fNode.name.staticElement, same(fElement));
    expect(fNode.name.staticType, fElement.type);

    TypeName fReturnTypeNode = fNode.returnType;
    expect(fReturnTypeNode.name.staticElement, same(doubleType.element));
    expect(fReturnTypeNode.type, doubleType);

    expect(fExpression.element, same(fElement));

    {
      List<ParameterElement> elements = fElement.parameters;
      expect(elements, hasLength(3));

      List<FormalParameter> nodes = fExpression.parameters.parameters;
      expect(nodes, hasLength(3));

      _assertSimpleParameter(nodes[0], elements[0],
          name: 'a',
          offset: 29,
          kind: ParameterKind.REQUIRED,
          type: typeProvider.intType);

      _assertDefaultParameter(nodes[1], elements[1],
          name: 'b',
          offset: 40,
          kind: ParameterKind.NAMED,
          type: typeProvider.stringType);

      _assertDefaultParameter(nodes[2], elements[2],
          name: 'c',
          offset: 48,
          kind: ParameterKind.NAMED,
          type: typeProvider.boolType);
    }

    {
      ExpressionStatement statement = mainStatements[1];
      MethodInvocation invocation = statement.expression;
      List<Expression> arguments = invocation.argumentList.arguments;

      _assertArgumentToParameter(arguments[0], fElement.parameters[0]);
      _assertArgumentToParameter(arguments[1], fElement.parameters[1]);
      _assertArgumentToParameter(arguments[2], fElement.parameters[2]);
    }
  }

  test_local_function_noReturnType() async {
    addTestFile(r'''
void main() {
  f() {}
}
''');

    await resolveTestFile();
    List<Statement> mainStatements = _getMainStatements(result);

    FunctionDeclarationStatement fStatement = mainStatements[0];
    FunctionDeclaration fNode = fStatement.functionDeclaration;
    FunctionExpression fExpression = fNode.functionExpression;
    FunctionElement fElement = fNode.element;

    expect(fNode.returnType, isNull);
    expect(fElement, isNotNull);
    expect(fElement.type.toString(), '() → Null');

    expect(fNode.name.staticElement, same(fElement));
    expect(fNode.name.staticType, fElement.type);

    expect(fExpression.element, same(fElement));
  }

  test_local_function_optionalParameters() async {
    addTestFile(r'''
void main() {
  double f(int a, [String b, bool c]) {}
  var v = f(1, '2', true);
}
''');
    String fTypeString = '(int, [String, bool]) → double';

    await resolveTestFile();
    List<Statement> mainStatements = _getMainStatements(result);

    InterfaceType doubleType = typeProvider.doubleType;

    FunctionDeclarationStatement fStatement = mainStatements[0];
    FunctionDeclaration fNode = fStatement.functionDeclaration;
    FunctionExpression fExpression = fNode.functionExpression;
    FunctionElement fElement = fNode.element;
    expect(fElement, isNotNull);
    expect(fElement.type.toString(), fTypeString);

    expect(fNode.name.staticElement, same(fElement));
    expect(fNode.name.staticType, fElement.type);

    TypeName fReturnTypeNode = fNode.returnType;
    expect(fReturnTypeNode.name.staticElement, same(doubleType.element));
    expect(fReturnTypeNode.type, doubleType);

    expect(fExpression.element, same(fElement));

    {
      List<ParameterElement> elements = fElement.parameters;
      expect(elements, hasLength(3));

      List<FormalParameter> nodes = fExpression.parameters.parameters;
      expect(nodes, hasLength(3));

      _assertSimpleParameter(nodes[0], elements[0],
          name: 'a',
          offset: 29,
          kind: ParameterKind.REQUIRED,
          type: typeProvider.intType);

      _assertDefaultParameter(nodes[1], elements[1],
          name: 'b',
          offset: 40,
          kind: ParameterKind.POSITIONAL,
          type: typeProvider.stringType);

      _assertDefaultParameter(nodes[2], elements[2],
          name: 'c',
          offset: 48,
          kind: ParameterKind.POSITIONAL,
          type: typeProvider.boolType);
    }

    {
      VariableDeclarationStatement statement = mainStatements[1];
      VariableDeclaration declaration = statement.variables.variables[0];
      expect(declaration.element.type, same(doubleType));

      MethodInvocation invocation = declaration.initializer;
      expect(invocation.methodName.staticElement, same(fElement));
      expect(invocation.methodName.staticType.toString(), fTypeString);
      expect(invocation.staticType, same(doubleType));
      expect(invocation.staticInvokeType.toString(), fTypeString);

      List<Expression> arguments = invocation.argumentList.arguments;
      _assertArgumentToParameter(arguments[0], fElement.parameters[0]);
      _assertArgumentToParameter(arguments[1], fElement.parameters[1]);
      _assertArgumentToParameter(arguments[2], fElement.parameters[2]);
    }
  }

  test_local_parameter() async {
    String content = r'''
void main(int p) {
  p;
}
''';
    addTestFile(content);

    await resolveTestFile();
    expect(result.path, testFile);
    expect(result.errors, isEmpty);

    InterfaceType intType = typeProvider.intType;

    FunctionDeclaration main = result.unit.declarations[0];
    List<Statement> statements = _getMainStatements(result);

    // (int p)
    VariableElement pElement = main.element.parameters[0];
    expect(pElement.type, intType);

    // p;
    {
      ExpressionStatement statement = statements[0];
      SimpleIdentifier identifier = statement.expression;
      expect(identifier.staticElement, pElement);
      expect(identifier.staticType, intType);
    }
  }

  test_local_parameter_ofLocalFunction() async {
    addTestFile(r'''
void main() {
  void f(int a) {
    a;
    void g(double b) {
      b;
    }
  }
}
''');
    await resolveTestFile();

    List<Statement> mainStatements = _getMainStatements(result);

    // f(int a) {}
    FunctionDeclarationStatement fStatement = mainStatements[0];
    FunctionDeclaration fNode = fStatement.functionDeclaration;
    FunctionExpression fExpression = fNode.functionExpression;
    FunctionElement fElement = fNode.element;
    ParameterElement aElement = fElement.parameters[0];
    _assertSimpleParameter(fExpression.parameters.parameters[0], aElement,
        name: 'a',
        offset: 27,
        kind: ParameterKind.REQUIRED,
        type: typeProvider.intType);

    BlockFunctionBody fBody = fExpression.body;
    List<Statement> fStatements = fBody.block.statements;

    // a;
    ExpressionStatement aStatement = fStatements[0];
    SimpleIdentifier aNode = aStatement.expression;
    expect(aNode.staticElement, same(aElement));
    expect(aNode.staticType, typeProvider.intType);

    // g(double b) {}
    FunctionDeclarationStatement gStatement = fStatements[1];
    FunctionDeclaration gNode = gStatement.functionDeclaration;
    FunctionExpression gExpression = gNode.functionExpression;
    FunctionElement gElement = gNode.element;
    ParameterElement bElement = gElement.parameters[0];
    _assertSimpleParameter(gExpression.parameters.parameters[0], bElement,
        name: 'b',
        offset: 57,
        kind: ParameterKind.REQUIRED,
        type: typeProvider.doubleType);

    BlockFunctionBody gBody = gExpression.body;
    List<Statement> gStatements = gBody.block.statements;

    // b;
    ExpressionStatement bStatement = gStatements[0];
    SimpleIdentifier bNode = bStatement.expression;
    expect(bNode.staticElement, same(bElement));
    expect(bNode.staticType, typeProvider.doubleType);
  }

  test_local_variable() async {
    addTestFile(r'''
void main() {
  var v = 42;
  v;
}
''');
    await resolveTestFile();
    expect(result.path, testFile);
    expect(result.errors, isEmpty);

    InterfaceType intType = typeProvider.intType;

    FunctionDeclaration main = result.unit.declarations[0];
    expect(main.element, isNotNull);
    expect(main.name.staticElement, isNotNull);
    expect(main.name.staticType.toString(), '() → void');

    BlockFunctionBody body = main.functionExpression.body;
    NodeList<Statement> statements = body.block.statements;

    // var v = 42;
    VariableElement vElement;
    {
      VariableDeclarationStatement statement = statements[0];
      VariableDeclaration vNode = statement.variables.variables[0];
      expect(vNode.name.staticType, intType);
      expect(vNode.initializer.staticType, intType);

      vElement = vNode.name.staticElement;
      expect(vElement, isNotNull);
      expect(vElement.type, isNotNull);
      expect(vElement.type, intType);
    }

    // v;
    {
      ExpressionStatement statement = statements[1];
      SimpleIdentifier identifier = statement.expression;
      expect(identifier.staticElement, same(vElement));
      expect(identifier.staticType, intType);
    }
  }

  test_local_variable_forIn_identifier_field() async {
    addTestFile(r'''
class C {
  num v;
  void foo() {
    for (v in <int>[]) {
      v;
    }
  }
}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cDeclaration = unit.declarations[0];

    FieldDeclaration vDeclaration = cDeclaration.members[0];
    VariableDeclaration vNode = vDeclaration.fields.variables[0];
    FieldElement vElement = vNode.element;
    expect(vElement.type, typeProvider.numType);

    MethodDeclaration fooDeclaration = cDeclaration.members[1];
    BlockFunctionBody fooBody = fooDeclaration.body;
    List<Statement> statements = fooBody.block.statements;

    ForEachStatement forEachStatement = statements[0];
    Block forBlock = forEachStatement.body;

    expect(forEachStatement.loopVariable, isNull);

    SimpleIdentifier vInFor = forEachStatement.identifier;
    expect(vInFor.staticElement, same(vElement.setter));
    expect(vInFor.staticType, typeProvider.numType);

    ExpressionStatement statement = forBlock.statements[0];
    SimpleIdentifier identifier = statement.expression;
    expect(identifier.staticElement, same(vElement.getter));
    expect(identifier.staticType, typeProvider.numType);
  }

  test_local_variable_forIn_identifier_localVariable() async {
    addTestFile(r'''
void main() {
  num v;
  for (v in <int>[]) {
    v;
  }
}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> statements = _getMainStatements(result);

    VariableDeclarationStatement vStatement = statements[0];
    VariableDeclaration vNode = vStatement.variables.variables[0];
    LocalVariableElement vElement = vNode.element;
    expect(vElement.type, typeProvider.numType);

    ForEachStatement forEachStatement = statements[1];
    Block forBlock = forEachStatement.body;

    expect(forEachStatement.loopVariable, isNull);

    SimpleIdentifier vInFor = forEachStatement.identifier;
    expect(vInFor.staticElement, vElement);
    expect(vInFor.staticType, typeProvider.numType);

    ExpressionStatement statement = forBlock.statements[0];
    SimpleIdentifier identifier = statement.expression;
    expect(identifier.staticElement, same(vElement));
    expect(identifier.staticType, typeProvider.numType);
  }

  test_local_variable_forIn_identifier_topLevelVariable() async {
    addTestFile(r'''
void main() {
  for (v in <int>[]) {
    v;
  }
}
num v;
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> statements = _getMainStatements(result);

    TopLevelVariableDeclaration vDeclaration = unit.declarations[1];
    VariableDeclaration vNode = vDeclaration.variables.variables[0];
    TopLevelVariableElement vElement = vNode.element;
    expect(vElement.type, typeProvider.numType);

    ForEachStatement forEachStatement = statements[0];
    Block forBlock = forEachStatement.body;

    expect(forEachStatement.loopVariable, isNull);

    SimpleIdentifier vInFor = forEachStatement.identifier;
    expect(vInFor.staticElement, same(vElement.setter));
    expect(vInFor.staticType, typeProvider.numType);

    ExpressionStatement statement = forBlock.statements[0];
    SimpleIdentifier identifier = statement.expression;
    expect(identifier.staticElement, same(vElement.getter));
    expect(identifier.staticType, typeProvider.numType);
  }

  test_local_variable_forIn_loopVariable() async {
    addTestFile(r'''
void main() {
  for (var v in <int>[]) {
    v;
  }
}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> statements = _getMainStatements(result);

    ForEachStatement forEachStatement = statements[0];
    Block forBlock = forEachStatement.body;

    DeclaredIdentifier vNode = forEachStatement.loopVariable;
    LocalVariableElement vElement = vNode.element;
    expect(vElement.type, typeProvider.intType);

    expect(vNode.identifier.staticElement, vElement);
    expect(vNode.identifier.staticType, typeProvider.intType);

    ExpressionStatement statement = forBlock.statements[0];
    SimpleIdentifier identifier = statement.expression;
    expect(identifier.staticElement, vElement);
    expect(identifier.staticType, typeProvider.intType);
  }

  test_local_variable_forIn_loopVariable_explicitType() async {
    addTestFile(r'''
void main() {
  for (num v in <int>[]) {
    v;
  }
}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> statements = _getMainStatements(result);

    ForEachStatement forEachStatement = statements[0];
    Block forBlock = forEachStatement.body;

    DeclaredIdentifier vNode = forEachStatement.loopVariable;
    LocalVariableElement vElement = vNode.element;
    expect(vElement.type, typeProvider.numType);

    TypeName vTypeName = vNode.type;
    expect(vTypeName.type, typeProvider.numType);

    SimpleIdentifier vTypeIdentifier = vTypeName.name;
    expect(vTypeIdentifier.staticElement, typeProvider.numType.element);
    expect(vTypeIdentifier.staticType, typeProvider.numType);

    expect(vNode.identifier.staticElement, vElement);
    expect(vNode.identifier.staticType, typeProvider.numType);

    ExpressionStatement statement = forBlock.statements[0];
    SimpleIdentifier identifier = statement.expression;
    expect(identifier.staticElement, vElement);
    expect(identifier.staticType, typeProvider.numType);
  }

  test_local_variable_multiple() async {
    addTestFile(r'''
void main() {
  var a = 1, b = 2.3;
}
''');
    await resolveTestFile();

    List<Statement> statements = _getMainStatements(result);

    VariableDeclarationStatement declarationStatement = statements[0];

    VariableDeclaration aNode = declarationStatement.variables.variables[0];
    LocalVariableElement aElement = aNode.element;
    expect(aElement.type, typeProvider.intType);

    VariableDeclaration bNode = declarationStatement.variables.variables[1];
    LocalVariableElement bElement = bNode.element;
    expect(bElement.type, typeProvider.doubleType);
  }

  test_local_variable_ofLocalFunction() async {
    addTestFile(r'''
void main() {
  void f() {
    int a;
    a;
    void g() {
      double b;
      a;
      b;
    }
  }
}
''');
    await resolveTestFile();

    List<Statement> mainStatements = _getMainStatements(result);

    // f() {}
    FunctionDeclarationStatement fStatement = mainStatements[0];
    FunctionDeclaration fNode = fStatement.functionDeclaration;
    BlockFunctionBody fBody = fNode.functionExpression.body;
    List<Statement> fStatements = fBody.block.statements;

    // int a;
    VariableDeclarationStatement aDeclaration = fStatements[0];
    VariableElement aElement = aDeclaration.variables.variables[0].element;

    // a;
    {
      ExpressionStatement aStatement = fStatements[1];
      SimpleIdentifier aNode = aStatement.expression;
      expect(aNode.staticElement, same(aElement));
      expect(aNode.staticType, typeProvider.intType);
    }

    // g(double b) {}
    FunctionDeclarationStatement gStatement = fStatements[2];
    FunctionDeclaration gNode = gStatement.functionDeclaration;
    BlockFunctionBody gBody = gNode.functionExpression.body;
    List<Statement> gStatements = gBody.block.statements;

    // double b;
    VariableDeclarationStatement bDeclaration = gStatements[0];
    VariableElement bElement = bDeclaration.variables.variables[0].element;

    // a;
    {
      ExpressionStatement aStatement = gStatements[1];
      SimpleIdentifier aNode = aStatement.expression;
      expect(aNode.staticElement, same(aElement));
      expect(aNode.staticType, typeProvider.intType);
    }

    // b;
    {
      ExpressionStatement bStatement = gStatements[2];
      SimpleIdentifier bNode = bStatement.expression;
      expect(bNode.staticElement, same(bElement));
      expect(bNode.staticType, typeProvider.doubleType);
    }
  }

  test_mapLiteral() async {
    addTestFile(r'''
void main() {
  <int, double>{};
  const <bool, String>{};
}
''');
    await resolveTestFile();

    var statements = _getMainStatements(result);

    {
      ExpressionStatement statement = statements[0];
      MapLiteral mapLiteral = statement.expression;
      expect(
          mapLiteral.staticType,
          typeProvider.mapType
              .instantiate([typeProvider.intType, typeProvider.doubleType]));
    }

    {
      ExpressionStatement statement = statements[1];
      MapLiteral mapLiteral = statement.expression;
      expect(
          mapLiteral.staticType,
          typeProvider.mapType
              .instantiate([typeProvider.boolType, typeProvider.stringType]));
    }
  }

  test_method_namedParameters() async {
    addTestFile(r'''
class C {
  double f(int a, {String b, bool c: false}) {}
}
void g(C c) {
  c.f(1, b: '2', c: true);
}
''');
    String fTypeString = '(int, {b: String, c: bool}) → double';

    await resolveTestFile();
    ClassDeclaration classDeclaration = result.unit.declarations[0];
    MethodDeclaration methodDeclaration = classDeclaration.members[0];
    MethodElement methodElement = methodDeclaration.element;

    InterfaceType doubleType = typeProvider.doubleType;

    expect(methodElement, isNotNull);
    expect(methodElement.type.toString(), fTypeString);

    expect(methodDeclaration.name.staticElement, same(methodElement));
    expect(methodDeclaration.name.staticType, methodElement.type);

    TypeName fReturnTypeNode = methodDeclaration.returnType;
    expect(fReturnTypeNode.name.staticElement, same(doubleType.element));
    expect(fReturnTypeNode.type, doubleType);
    //
    // Validate the parameters at the declaration site.
    //
    List<ParameterElement> elements = methodElement.parameters;
    expect(elements, hasLength(3));

    List<FormalParameter> nodes = methodDeclaration.parameters.parameters;
    expect(nodes, hasLength(3));

    _assertSimpleParameter(nodes[0], elements[0],
        name: 'a',
        offset: 25,
        kind: ParameterKind.REQUIRED,
        type: typeProvider.intType);

    _assertDefaultParameter(nodes[1], elements[1],
        name: 'b',
        offset: 36,
        kind: ParameterKind.NAMED,
        type: typeProvider.stringType);

    _assertDefaultParameter(nodes[2], elements[2],
        name: 'c',
        offset: 44,
        kind: ParameterKind.NAMED,
        type: typeProvider.boolType);
    //
    // Validate the arguments at the call site.
    //
    FunctionDeclaration functionDeclaration = result.unit.declarations[1];
    BlockFunctionBody body = functionDeclaration.functionExpression.body;
    ExpressionStatement statement = body.block.statements[0];
    MethodInvocation invocation = statement.expression;

    List<Expression> arguments = invocation.argumentList.arguments;
    _assertArgumentToParameter(arguments[0], methodElement.parameters[0]);
    _assertArgumentToParameter(arguments[1], methodElement.parameters[1]);
    _assertArgumentToParameter(arguments[2], methodElement.parameters[2]);
  }

  test_methodInvocation_explicitCall_classTarget() async {
    addTestFile(r'''
class C {
  double call(int p) => 0.0;
}
main() {
  new C().call(0);
}
''');
    await resolveTestFile();
    expect(result.errors, isEmpty);

    ClassDeclaration cNode = result.unit.declarations[0];
    ClassElement cElement = cNode.element;
    MethodElement callElement = cElement.methods[0];

    List<Statement> statements = _getMainStatements(result);

    ExpressionStatement statement = statements[0];
    MethodInvocation invocation = statement.expression;

    expect(invocation.staticType, typeProvider.doubleType);
    expect(invocation.staticInvokeType.toString(), '(int) → double');

    SimpleIdentifier methodName = invocation.methodName;
    expect(methodName.staticElement, same(callElement));
    expect(methodName.staticType.toString(), '(int) → double');
  }

  test_methodInvocation_explicitCall_functionTarget() async {
    addTestFile(r'''
main(double computation(int p)) {
  computation.call(1);
}
''');
    await resolveTestFile();
    expect(result.errors, isEmpty);

    FunctionDeclaration main = result.unit.declarations[0];
    FunctionElement mainElement = main.element;
    ParameterElement parameter = mainElement.parameters[0];

    BlockFunctionBody mainBody = main.functionExpression.body;
    List<Statement> statements = mainBody.block.statements;

    ExpressionStatement statement = statements[0];
    MethodInvocation invocation = statement.expression;

    expect(invocation.staticType, typeProvider.doubleType);
    expect(invocation.staticInvokeType.toString(), '(int) → double');

    SimpleIdentifier target = invocation.target;
    expect(target.staticElement, same(parameter));
    expect(target.staticType.toString(), '(int) → double');

    SimpleIdentifier methodName = invocation.methodName;
    if (useCFE) {
      expect(methodName.staticElement, isNull);
      expect(methodName.staticType, isNull);
    } else {
      expect(methodName.staticElement, same(parameter));
      expect(methodName.staticType, parameter.type);
    }
  }

  test_methodInvocation_instanceMethod_forwardingStub() async {
    addTestFile(r'''
class A {
  void foo(int x) {}
}
abstract class I<T> {
  void foo(T x);
}
class B extends A implements I<int> {}
main(B b) {
  b.foo(1);
}
''');
    await resolveTestFile();

    ClassDeclaration aNode = result.unit.declarations[0];
    MethodDeclaration fooNode = aNode.members[0];
    MethodElement fooElement = fooNode.element;

    List<Statement> mainStatements = _getMainStatements(result);
    ExpressionStatement statement = mainStatements[0];
    MethodInvocation invocation = statement.expression;
    expect(invocation.methodName.staticElement, same(fooElement));

    var invokeTypeStr = '(int) → void';
    expect(invocation.staticType.toString(), 'void');
    expect(invocation.staticInvokeType.toString(), invokeTypeStr);
  }

  test_methodInvocation_instanceMethod_genericClass() async {
    addTestFile(r'''
main() {
  new C<int, double>().m(1);
}
class C<T, U> {
  void m(T p) {}
}
''');
    await resolveTestFile();
    List<Statement> mainStatements = _getMainStatements(result);

    ClassDeclaration cNode = result.unit.declarations[1];
    MethodDeclaration mNode = cNode.members[0];
    MethodElement mElement = mNode.element;

    {
      ExpressionStatement statement = mainStatements[0];
      MethodInvocation invocation = statement.expression;
      List<Expression> arguments = invocation.argumentList.arguments;

      var invokeTypeStr = '(int) → void';
      expect(invocation.staticType.toString(), 'void');
      expect(invocation.staticInvokeType.toString(), invokeTypeStr);
      if (useCFE) {
        expect(invocation.methodName.staticElement, same(mElement));
        expect(invocation.methodName.staticType.toString(), invokeTypeStr);
      } else {
        expect(invocation.staticInvokeType.element, same(mElement));
      }

      _assertArgumentToParameter(arguments[0], mElement.parameters[0]);
    }
  }

  test_methodInvocation_instanceMethod_genericClass_genericMethod() async {
    addTestFile(r'''
main() {
  new C<int>().m(1, 2.3);
}
class C<T> {
  Map<T, U> m<U>(T a, U b) => null;
}
''');
    await resolveTestFile();

    List<Statement> mainStatements = _getMainStatements(result);

    ClassDeclaration cNode = result.unit.declarations[1];
    MethodDeclaration mNode = cNode.members[0];
    MethodElement mElement = mNode.element;

    {
      ExpressionStatement statement = mainStatements[0];
      MethodInvocation invocation = statement.expression;
      List<Expression> arguments = invocation.argumentList.arguments;

      var invokeTypeStr = '(int, double) → Map<int, double>';
      expect(invocation.staticType.toString(), 'Map<int, double>');
      expect(invocation.staticInvokeType.toString(), invokeTypeStr);
      if (useCFE) {
        expect(invocation.methodName.staticElement, same(mElement));
        expect(invocation.methodName.staticType.toString(), invokeTypeStr);
      }

      if (useCFE) {
        expect(arguments[0].staticParameterElement, isNull);
        expect(arguments[1].staticParameterElement, isNull);
      } else {
        Expression aArgument = arguments[0];
        ParameterMember aArgumentParameter = aArgument.staticParameterElement;
        ParameterElement aElement = mElement.parameters[0];
        expect(aArgumentParameter.type, typeProvider.intType);
        expect(aArgumentParameter.baseElement, same(aElement));

        Expression bArgument = arguments[1];
        ParameterMember bArgumentParameter = bArgument.staticParameterElement;
        expect(bArgumentParameter.type, typeProvider.doubleType);
      }
    }
  }

  test_methodInvocation_namedArgument() async {
    addTestFile(r'''
void main() {
  foo(1, b: true, c: 3.0);
}
void foo(int a, {bool b, double c}) {}
''');
    await resolveTestFile();
    List<Statement> mainStatements = _getMainStatements(result);

    FunctionDeclaration foo = result.unit.declarations[1];
    ExecutableElement fooElement = foo.element;

    ExpressionStatement statement = mainStatements[0];
    MethodInvocation invocation = statement.expression;
    List<Expression> arguments = invocation.argumentList.arguments;

    _assertArgumentToParameter(arguments[0], fooElement.parameters[0]);
    _assertArgumentToParameter(arguments[1], fooElement.parameters[1]);
    _assertArgumentToParameter(arguments[2], fooElement.parameters[2]);
  }

  test_methodInvocation_notFunction_field_dynamic() async {
    addTestFile(r'''
class C {
  dynamic f;
  foo() {
    f(1);
  }
}
''');
    await resolveTestFile();

    ClassDeclaration cDeclaration = result.unit.declarations[0];

    FieldDeclaration fDeclaration = cDeclaration.members[0];
    VariableDeclaration fNode = fDeclaration.fields.variables[0];
    FieldElement fElement = fNode.element;

    MethodDeclaration fooDeclaration = cDeclaration.members[1];
    BlockFunctionBody fooBody = fooDeclaration.body;
    List<Statement> fooStatements = fooBody.block.statements;

    ExpressionStatement statement = fooStatements[0];
    MethodInvocation invocation = statement.expression;
    expect(invocation.methodName.staticElement, same(fElement.getter));
    if (useCFE) {
      _assertDynamicFunctionType(invocation.staticInvokeType);
    } else {
      expect(invocation.staticInvokeType, DynamicTypeImpl.instance);
    }
    expect(invocation.staticType, DynamicTypeImpl.instance);

    List<Expression> arguments = invocation.argumentList.arguments;
    expect(arguments[0].staticParameterElement, isNull);
  }

  test_methodInvocation_notFunction_getter_dynamic() async {
    addTestFile(r'''
class C {
  get f => null;
  foo() {
    f(1);
  }
}
''');
    await resolveTestFile();

    ClassDeclaration cDeclaration = result.unit.declarations[0];

    MethodDeclaration fDeclaration = cDeclaration.members[0];
    PropertyAccessorElement fElement = fDeclaration.element;

    MethodDeclaration fooDeclaration = cDeclaration.members[1];
    BlockFunctionBody fooBody = fooDeclaration.body;
    List<Statement> fooStatements = fooBody.block.statements;

    ExpressionStatement statement = fooStatements[0];
    MethodInvocation invocation = statement.expression;
    expect(invocation.methodName.staticElement, same(fElement));
    if (useCFE) {
      _assertDynamicFunctionType(invocation.staticInvokeType);
    } else {
      expect(invocation.staticInvokeType, DynamicTypeImpl.instance);
    }
    expect(invocation.staticType, DynamicTypeImpl.instance);

    List<Expression> arguments = invocation.argumentList.arguments;

    Expression argument = arguments[0];
    expect(argument.staticParameterElement, isNull);
  }

  test_methodInvocation_notFunction_getter_typedef() async {
    addTestFile(r'''
typedef String Fun(int a, {int b});
class C {
  Fun get f => null;
  foo() {
    f(1, b: 2);
  }
}
''');
    await resolveTestFile();

    FunctionTypeAlias funDeclaration = result.unit.declarations[0];
    FunctionTypeAliasElement funElement = funDeclaration.element;

    ClassDeclaration cDeclaration = result.unit.declarations[1];

    MethodDeclaration fDeclaration = cDeclaration.members[0];
    PropertyAccessorElement fElement = fDeclaration.element;

    MethodDeclaration fooDeclaration = cDeclaration.members[1];
    BlockFunctionBody fooBody = fooDeclaration.body;
    List<Statement> fooStatements = fooBody.block.statements;

    ExpressionStatement statement = fooStatements[0];
    MethodInvocation invocation = statement.expression;
    expect(invocation.methodName.staticElement, same(fElement));
    expect(invocation.staticInvokeType.toString(), '(int, {b: int}) → String');
    expect(invocation.staticType, typeProvider.stringType);

    List<Expression> arguments = invocation.argumentList.arguments;
    _assertArgumentToParameter(arguments[0], funElement.parameters[0]);
    _assertArgumentToParameter(arguments[1], funElement.parameters[1]);
  }

  test_methodInvocation_notFunction_local_dynamic() async {
    addTestFile(r'''
main(f) {
  f(1);
}
''');
    await resolveTestFile();

    FunctionDeclaration mainDeclaration = result.unit.declarations[0];
    FunctionExpression mainFunction = mainDeclaration.functionExpression;
    ParameterElement fElement = mainFunction.parameters.parameters[0].element;

    BlockFunctionBody mainBody = mainFunction.body;
    List<Statement> mainStatements = mainBody.block.statements;

    ExpressionStatement statement = mainStatements[0];
    MethodInvocation invocation = statement.expression;
    expect(invocation.methodName.staticElement, same(fElement));
    _assertDynamicFunctionType(invocation.staticInvokeType);
    expect(invocation.staticType, DynamicTypeImpl.instance);

    List<Expression> arguments = invocation.argumentList.arguments;

    Expression argument = arguments[0];
    expect(argument.staticParameterElement, isNull);
  }

  test_methodInvocation_notFunction_local_functionTyped() async {
    addTestFile(r'''
main(String f(int a)) {
  f(1);
}
''');
    await resolveTestFile();

    FunctionDeclaration mainDeclaration = result.unit.declarations[0];
    FunctionExpression mainFunction = mainDeclaration.functionExpression;
    ParameterElement fElement = mainFunction.parameters.parameters[0].element;

    BlockFunctionBody mainBody = mainFunction.body;
    List<Statement> mainStatements = mainBody.block.statements;

    ExpressionStatement statement = mainStatements[0];
    MethodInvocation invocation = statement.expression;
    expect(invocation.methodName.staticElement, same(fElement));
    expect(invocation.staticInvokeType.toString(), '(int) → String');
    expect(invocation.staticType, typeProvider.stringType);

    List<Expression> arguments = invocation.argumentList.arguments;
    _assertArgumentToParameter(
        arguments[0], (fElement.type as FunctionType).parameters[0]);
  }

  test_methodInvocation_notFunction_topLevelVariable_dynamic() async {
    addTestFile(r'''
dynamic f;
main() {
  f(1);
}
''');
    await resolveTestFile();

    TopLevelVariableDeclaration fDeclaration = result.unit.declarations[0];
    VariableDeclaration fNode = fDeclaration.variables.variables[0];
    TopLevelVariableElement fElement = fNode.element;

    List<Statement> mainStatements = _getMainStatements(result);

    ExpressionStatement statement = mainStatements[0];
    MethodInvocation invocation = statement.expression;
    expect(invocation.methodName.staticElement, same(fElement.getter));
    _assertDynamicFunctionType(invocation.staticInvokeType);
    expect(invocation.staticType, DynamicTypeImpl.instance);

    List<Expression> arguments = invocation.argumentList.arguments;

    Expression argument = arguments[0];
    expect(argument.staticParameterElement, isNull);
  }

  test_methodInvocation_staticMethod() async {
    addTestFile(r'''
main() {
  C.m(1);
}
class C {
  static void m(int p) {}
  void foo() {
    m(2);
  }
}
''');
    await resolveTestFile();
    List<Statement> mainStatements = _getMainStatements(result);

    ClassDeclaration cNode = result.unit.declarations[1];
    ClassElement cElement = cNode.element;
    MethodDeclaration mNode = cNode.members[0];
    MethodElement mElement = mNode.element;

    {
      ExpressionStatement statement = mainStatements[0];
      MethodInvocation invocation = statement.expression;
      List<Expression> arguments = invocation.argumentList.arguments;

      SimpleIdentifier target = invocation.target;
      expect(target.staticElement, same(cElement));
      expect(target.staticType, same(cElement.type));

      var invokeTypeStr = '(int) → void';
      expect(invocation.staticType.toString(), 'void');
      expect(invocation.staticInvokeType.toString(), invokeTypeStr);
      if (!useCFE) {
        expect(invocation.staticInvokeType.element, same(mElement));
      }
      expect(invocation.methodName.staticElement, same(mElement));
      expect(invocation.methodName.staticType.toString(), invokeTypeStr);

      Expression argument = arguments[0];
      _assertArgumentToParameter(argument, mElement.parameters[0]);
    }

    {
      MethodDeclaration fooNode = cNode.members[1];
      BlockFunctionBody fooBody = fooNode.body;
      List<Statement> statements = fooBody.block.statements;

      ExpressionStatement statement = statements[0];
      MethodInvocation invocation = statement.expression;
      List<Expression> arguments = invocation.argumentList.arguments;

      expect(invocation.target, isNull);

      var invokeTypeStr = '(int) → void';
      expect(invocation.staticType.toString(), 'void');
      expect(invocation.staticInvokeType.toString(), invokeTypeStr);
      if (!useCFE) {
        expect(invocation.staticInvokeType.element, same(mElement));
      }
      expect(invocation.methodName.staticElement, same(mElement));
      expect(invocation.methodName.staticType.toString(), invokeTypeStr);

      Expression argument = arguments[0];
      _assertArgumentToParameter(argument, mElement.parameters[0]);
    }
  }

  test_methodInvocation_staticMethod_contextTypeParameter() async {
    addTestFile(r'''
class C<T> {
  static E foo<E>(C<E> c) => null;
  void bar() {
    foo(this);
  }
}
''');
    await resolveTestFile();

    ClassDeclaration cNode = result.unit.declarations[0];
    TypeParameterElement tElement = cNode.element.typeParameters[0];

    MethodDeclaration barNode = cNode.members[1];
    BlockFunctionBody barBody = barNode.body;
    ExpressionStatement fooStatement = barBody.block.statements[0];
    MethodInvocation fooInvocation = fooStatement.expression;
    expect(fooInvocation.staticInvokeType.toString(), '(C<T>) → T');
    expect(fooInvocation.staticType.toString(), 'T');
    expect(fooInvocation.staticType.element, same(tElement));
  }

  test_methodInvocation_topLevelFunction() async {
    addTestFile(r'''
void main() {
  f(1, '2');
}
double f(int a, String b) {}
''');
    String fTypeString = '(int, String) → double';

    await resolveTestFile();
    List<Statement> mainStatements = _getMainStatements(result);

    InterfaceType doubleType = typeProvider.doubleType;

    FunctionDeclaration fNode = result.unit.declarations[1];
    FunctionElement fElement = fNode.element;

    ExpressionStatement statement = mainStatements[0];
    MethodInvocation invocation = statement.expression;
    List<Expression> arguments = invocation.argumentList.arguments;

    expect(invocation.methodName.staticElement, same(fElement));
    expect(invocation.methodName.staticType.toString(), fTypeString);
    expect(invocation.staticType, same(doubleType));
    expect(invocation.staticInvokeType.toString(), fTypeString);

    _assertArgumentToParameter(arguments[0], fElement.parameters[0]);
    _assertArgumentToParameter(arguments[1], fElement.parameters[1]);
  }

  test_methodInvocation_topLevelFunction_generic() async {
    addTestFile(r'''
void main() {
  f<bool, String>(true, 'str');
  f(1, 2.3);
}
void f<T, U>(T a, U b) {}
''');
    await resolveTestFile();

    List<Statement> mainStatements = _getMainStatements(result);

    FunctionDeclaration fNode = result.unit.declarations[1];
    FunctionElement fElement = fNode.element;

    // f<bool, String>(true, 'str');
    {
      String fTypeString = '(bool, String) → void';
      ExpressionStatement statement = mainStatements[0];
      MethodInvocation invocation = statement.expression;

      List<TypeAnnotation> typeArguments = invocation.typeArguments.arguments;
      expect(typeArguments, hasLength(2));
      {
        TypeName typeArgument = typeArguments[0];
        InterfaceType boolType = typeProvider.boolType;
        expect(typeArgument.type, boolType);
        expect(typeArgument.name.staticElement, boolType.element);
        expect(typeArgument.name.staticType, boolType);
      }
      {
        TypeName typeArgument = typeArguments[1];
        InterfaceType stringType = typeProvider.stringType;
        expect(typeArgument.type, stringType);
        expect(typeArgument.name.staticElement, stringType.element);
        expect(typeArgument.name.staticType, stringType);
      }

      List<Expression> arguments = invocation.argumentList.arguments;

      expect(invocation.methodName.staticElement, same(fElement));
      if (useCFE) {
        expect(invocation.methodName.staticType.toString(), fTypeString);
      }
      expect(invocation.staticType, VoidTypeImpl.instance);
      expect(invocation.staticInvokeType.toString(), fTypeString);

      _assertArgumentToParameter(arguments[0], fElement.parameters[0],
          parameterMemberType: typeProvider.boolType);
      _assertArgumentToParameter(arguments[1], fElement.parameters[1],
          parameterMemberType: typeProvider.stringType);
    }

    // f(1, 2.3);
    {
      String fTypeString = '(int, double) → void';
      ExpressionStatement statement = mainStatements[1];
      MethodInvocation invocation = statement.expression;
      List<Expression> arguments = invocation.argumentList.arguments;

      expect(invocation.methodName.staticElement, same(fElement));
      if (useCFE) {
        expect(invocation.methodName.staticType.toString(), fTypeString);
      }
      expect(invocation.staticType, VoidTypeImpl.instance);
      expect(invocation.staticInvokeType.toString(), fTypeString);

      _assertArgumentToParameter(arguments[0], fElement.parameters[0],
          parameterMemberType: typeProvider.intType);
      _assertArgumentToParameter(arguments[1], fElement.parameters[1],
          parameterMemberType: typeProvider.doubleType);
    }
  }

  test_postfixExpression_local() async {
    String content = r'''
main() {
  int v = 0;
  v++;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> mainStatements = _getMainStatements(result);

    VariableElement v;
    {
      VariableDeclarationStatement statement = mainStatements[0];
      v = statement.variables.variables[0].element;
      expect(v.type, typeProvider.intType);
    }

    {
      ExpressionStatement statement = mainStatements[1];

      PostfixExpression postfix = statement.expression;
      expect(postfix.operator.type, TokenType.PLUS_PLUS);
      expect(postfix.staticElement.name, '+');
      expect(postfix.staticType, typeProvider.intType);

      SimpleIdentifier operand = postfix.operand;
      expect(operand.staticElement, same(v));
      expect(operand.staticType, typeProvider.intType);
    }
  }

  test_postfixExpression_propertyAccess() async {
    String content = r'''
main() {
  new C().f++;
}
class C {
  int f;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cClassDeclaration = unit.declarations[1];
    ClassElement cClassElement = cClassDeclaration.element;
    FieldElement fElement = cClassElement.getField('f');

    List<Statement> mainStatements = _getMainStatements(result);

    {
      ExpressionStatement statement = mainStatements[0];

      PostfixExpression postfix = statement.expression;
      expect(postfix.operator.type, TokenType.PLUS_PLUS);
      expect(postfix.staticElement.name, '+');
      expect(postfix.staticType, typeProvider.intType);

      PropertyAccess propertyAccess = postfix.operand;
      expect(propertyAccess.staticType, typeProvider.intType);

      SimpleIdentifier propertyName = propertyAccess.propertyName;
      expect(propertyName.staticElement, same(fElement.setter));
      expect(propertyName.staticType, typeProvider.intType);
    }
  }

  test_prefixedIdentifier_classInstance_instanceField() async {
    String content = r'''
main() {
  var c = new C();
  c.f;
}
class C {
  int f;
}
''';
    addTestFile(content);

    await resolveTestFile();

    List<Statement> statements = _getMainStatements(result);

    ClassDeclaration cDeclaration = result.unit.declarations[1];
    ClassElement cElement = cDeclaration.element;
    FieldElement fElement = cElement.fields[0];

    VariableDeclarationStatement cStatement = statements[0];
    VariableElement vElement = cStatement.variables.variables[0].element;

    ExpressionStatement statement = statements[1];
    PrefixedIdentifier prefixed = statement.expression;

    SimpleIdentifier prefix = prefixed.prefix;
    expect(prefix.staticElement, same(vElement));
    expect(prefix.staticType, cElement.type);

    SimpleIdentifier identifier = prefixed.identifier;
    expect(identifier.staticElement, same(fElement.getter));
    expect(identifier.staticType, typeProvider.intType);
  }

  test_prefixedIdentifier_className_staticField() async {
    String content = r'''
main() {
  C.f;
}
class C {
  static f = 0;
}
''';
    addTestFile(content);

    await resolveTestFile();

    List<Statement> statements = _getMainStatements(result);

    ClassDeclaration cDeclaration = result.unit.declarations[1];
    ClassElement cElement = cDeclaration.element;
    FieldElement fElement = cElement.fields[0];

    ExpressionStatement statement = statements[0];
    PrefixedIdentifier prefixed = statement.expression;

    SimpleIdentifier prefix = prefixed.prefix;
    expect(prefix.staticElement, same(cElement));
    expect(prefix.staticType, cElement.type);

    SimpleIdentifier identifier = prefixed.identifier;
    expect(identifier.staticElement, same(fElement.getter));
    expect(identifier.staticType, typeProvider.intType);
  }

  test_prefixedIdentifier_explicitCall() async {
    addTestFile(r'''
main(double computation(int p)) {
  computation.call;
}
''');
    await resolveTestFile();
    expect(result.errors, isEmpty);

    FunctionDeclaration main = result.unit.declarations[0];
    FunctionElement mainElement = main.element;
    ParameterElement parameter = mainElement.parameters[0];

    BlockFunctionBody mainBody = main.functionExpression.body;
    List<Statement> statements = mainBody.block.statements;

    ExpressionStatement statement = statements[0];
    PrefixedIdentifier prefixed = statement.expression;

    expect(prefixed.prefix.staticElement, same(parameter));
    expect(prefixed.prefix.staticType.toString(), '(int) → double');

    SimpleIdentifier methodName = prefixed.identifier;
    expect(methodName.staticElement, isNull);
    if (useCFE) {
      expect(methodName.staticType, isNull);
    } else {
      expect(methodName.staticType, typeProvider.dynamicType);
    }
  }

  test_prefixedIdentifier_importPrefix_className() async {
    var libPath = _p('/test/lib/lib.dart');
    provider.newFile(libPath, '''
class MyClass {}
typedef void MyFunctionTypeAlias();
int myTopVariable;
int myTopFunction() => 0;
int get myGetter => 0;
void set mySetter(int _) {}
''');
    addTestFile(r'''
import 'lib.dart' as my;
main() {
  my.MyClass;
  my.MyFunctionTypeAlias;
  my.myTopVariable;
  my.myTopFunction;
  my.myTopFunction();
  my.myGetter;
  my.mySetter = 0;
}
''');
    await resolveTestFile();
    // TODO(scheglov) Uncomment and fix "unused imports" hint.
//    expect(result.errors, isEmpty);

    var unitElement = result.unit.element;
    ImportElement myImport = unitElement.library.imports[0];
    PrefixElement myPrefix = myImport.prefix;
    var typeProvider = unitElement.context.typeProvider;

    var myLibrary = myImport.importedLibrary;
    var myUnit = myLibrary.definingCompilationUnit;
    var myClass = myUnit.types.single;
    var myFunctionTypeAlias = myUnit.functionTypeAliases.single;
    var myTopVariable = myUnit.topLevelVariables[0];
    var myTopFunction = myUnit.functions.single;
    var myGetter = myUnit.topLevelVariables[1].getter;
    var mySetter = myUnit.topLevelVariables[2].setter;
    expect(myTopVariable.name, 'myTopVariable');
    expect(myGetter.displayName, 'myGetter');
    expect(mySetter.displayName, 'mySetter');

    List<Statement> statements = _getMainStatements(result);

    void assertPrefix(SimpleIdentifier identifier) {
      expect(identifier.staticElement, same(myPrefix));
      expect(identifier.staticType, isNull);
    }

    void assertPrefixedIdentifier(
        int statementIndex, Element expectedElement, DartType expectedType) {
      ExpressionStatement statement = statements[statementIndex];
      PrefixedIdentifier prefixed = statement.expression;
      assertPrefix(prefixed.prefix);

      expect(prefixed.identifier.staticElement, same(expectedElement));
      expect(prefixed.identifier.staticType, expectedType);
    }

    assertPrefixedIdentifier(0, myClass, typeProvider.typeType);
    assertPrefixedIdentifier(1, myFunctionTypeAlias, typeProvider.typeType);
    assertPrefixedIdentifier(2, myTopVariable.getter, typeProvider.intType);

    {
      ExpressionStatement statement = statements[3];
      PrefixedIdentifier prefixed = statement.expression;
      assertPrefix(prefixed.prefix);

      expect(prefixed.identifier.staticElement, same(myTopFunction));
      expect(prefixed.identifier.staticType, isNotNull);
    }

    {
      ExpressionStatement statement = statements[4];
      MethodInvocation invocation = statement.expression;
      assertPrefix(invocation.target);

      expect(invocation.methodName.staticElement, same(myTopFunction));
      expect(invocation.methodName.staticType, isNotNull);
    }

    assertPrefixedIdentifier(5, myGetter, typeProvider.intType);

    {
      ExpressionStatement statement = statements[6];
      AssignmentExpression assignment = statement.expression;
      PrefixedIdentifier left = assignment.leftHandSide;
      assertPrefix(left.prefix);

      expect(left.identifier.staticElement, same(mySetter));
      expect(left.identifier.staticType, typeProvider.intType);
    }
  }

  test_prefixExpression_local() async {
    String content = r'''
main() {
  int v = 0;
  ++v;
  ~v;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> mainStatements = _getMainStatements(result);

    VariableElement v;
    {
      VariableDeclarationStatement statement = mainStatements[0];
      v = statement.variables.variables[0].element;
      expect(v.type, typeProvider.intType);
    }

    {
      ExpressionStatement statement = mainStatements[1];

      PrefixExpression prefix = statement.expression;
      expect(prefix.operator.type, TokenType.PLUS_PLUS);
      expect(prefix.staticElement.name, '+');
      expect(prefix.staticType, typeProvider.intType);

      SimpleIdentifier operand = prefix.operand;
      expect(operand.staticElement, same(v));
      expect(operand.staticType, typeProvider.intType);
    }

    {
      ExpressionStatement statement = mainStatements[2];

      PrefixExpression prefix = statement.expression;
      expect(prefix.operator.type, TokenType.TILDE);
      expect(prefix.staticElement.name, '~');
      expect(prefix.staticType, typeProvider.intType);

      SimpleIdentifier operand = prefix.operand;
      expect(operand.staticElement, same(v));
      expect(operand.staticType, typeProvider.intType);
    }
  }

  test_prefixExpression_local_not() async {
    String content = r'''
main() {
  bool v = true;
  !v;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> mainStatements = _getMainStatements(result);

    VariableElement v;
    {
      VariableDeclarationStatement statement = mainStatements[0];
      v = statement.variables.variables[0].element;
      expect(v.type, typeProvider.boolType);
    }

    {
      ExpressionStatement statement = mainStatements[1];

      PrefixExpression prefix = statement.expression;
      expect(prefix.operator.type, TokenType.BANG);
      expect(prefix.staticElement, isNull);
      expect(prefix.staticType, typeProvider.boolType);

      SimpleIdentifier operand = prefix.operand;
      expect(operand.staticElement, same(v));
      expect(operand.staticType, typeProvider.boolType);
    }
  }

  test_prefixExpression_propertyAccess() async {
    String content = r'''
main() {
  ++new C().f;
  ~new C().f;
}
class C {
  int f;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cClassDeclaration = unit.declarations[1];
    ClassElement cClassElement = cClassDeclaration.element;
    FieldElement fElement = cClassElement.getField('f');

    List<Statement> mainStatements = _getMainStatements(result);

    {
      ExpressionStatement statement = mainStatements[0];

      PrefixExpression prefix = statement.expression;
      expect(prefix.operator.type, TokenType.PLUS_PLUS);
      expect(prefix.staticElement.name, '+');
      expect(prefix.staticType, typeProvider.intType);

      PropertyAccess propertyAccess = prefix.operand;
      expect(propertyAccess.staticType, typeProvider.intType);

      SimpleIdentifier propertyName = propertyAccess.propertyName;
      expect(propertyName.staticElement, same(fElement.setter));
      expect(propertyName.staticType, typeProvider.intType);
    }

    {
      ExpressionStatement statement = mainStatements[1];

      PrefixExpression prefix = statement.expression;
      expect(prefix.operator.type, TokenType.TILDE);
      expect(prefix.staticElement.name, '~');
      expect(prefix.staticType, typeProvider.intType);

      PropertyAccess propertyAccess = prefix.operand;
      expect(propertyAccess.staticType, typeProvider.intType);

      SimpleIdentifier propertyName = propertyAccess.propertyName;
      expect(propertyName.staticElement, same(fElement.getter));
      expect(propertyName.staticType, typeProvider.intType);
    }
  }

  test_propertyAccess_field() async {
    String content = r'''
main() {
  new C().f;
}
class C {
  int f;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cClassDeclaration = unit.declarations[1];
    ClassElement cClassElement = cClassDeclaration.element;
    FieldElement fElement = cClassElement.getField('f');

    List<Statement> mainStatements = _getMainStatements(result);

    {
      ExpressionStatement statement = mainStatements[0];
      PropertyAccess access = statement.expression;
      expect(access.staticType, typeProvider.intType);

      InstanceCreationExpression newC = access.target;
      expect(newC.staticElement, cClassElement.unnamedConstructor);
      expect(newC.staticType, cClassElement.type);

      expect(access.propertyName.staticElement, same(fElement.getter));
      expect(access.propertyName.staticType, typeProvider.intType);
    }
  }

  test_propertyAccess_getter() async {
    String content = r'''
main() {
  new C().f;
}
class C {
  int get f => 0;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    ClassDeclaration cClassDeclaration = unit.declarations[1];
    ClassElement cClassElement = cClassDeclaration.element;
    FieldElement fElement = cClassElement.getField('f');

    List<Statement> mainStatements = _getMainStatements(result);

    {
      ExpressionStatement statement = mainStatements[0];
      PropertyAccess access = statement.expression;
      expect(access.staticType, typeProvider.intType);

      InstanceCreationExpression newC = access.target;
      expect(newC.staticElement, cClassElement.unnamedConstructor);
      expect(newC.staticType, cClassElement.type);

      expect(access.propertyName.staticElement, same(fElement.getter));
      expect(access.propertyName.staticType, typeProvider.intType);
    }
  }

  test_stringInterpolation() async {
    String content = r'''
void main() {
  var v = 42;
  '$v$v $v';
  ' ${v + 1} ';
}
''';
    addTestFile(content);

    await resolveTestFile();
    expect(result.path, testFile);
    expect(result.errors, isEmpty);

    FunctionDeclaration main = result.unit.declarations[0];
    expect(main.element, isNotNull);
    expect(main.name.staticElement, isNotNull);
    expect(main.name.staticType.toString(), '() → void');

    BlockFunctionBody body = main.functionExpression.body;
    NodeList<Statement> statements = body.block.statements;

    // var v = 42;
    VariableElement vElement;
    {
      VariableDeclarationStatement statement = statements[0];
      vElement = statement.variables.variables[0].name.staticElement;
    }

    {
      ExpressionStatement statement = statements[1];
      StringInterpolation interpolation = statement.expression;

      InterpolationExpression element_1 = interpolation.elements[1];
      SimpleIdentifier expression_1 = element_1.expression;
      expect(expression_1.staticElement, same(vElement));
      expect(expression_1.staticType, typeProvider.intType);

      InterpolationExpression element_3 = interpolation.elements[3];
      SimpleIdentifier expression_3 = element_3.expression;
      expect(expression_3.staticElement, same(vElement));
      expect(expression_3.staticType, typeProvider.intType);

      InterpolationExpression element_5 = interpolation.elements[5];
      SimpleIdentifier expression_5 = element_5.expression;
      expect(expression_5.staticElement, same(vElement));
      expect(expression_5.staticType, typeProvider.intType);
    }

    {
      ExpressionStatement statement = statements[2];
      StringInterpolation interpolation = statement.expression;

      InterpolationExpression element_1 = interpolation.elements[1];
      BinaryExpression expression = element_1.expression;
      expect(expression.staticType, typeProvider.intType);

      SimpleIdentifier left = expression.leftOperand;
      expect(left.staticElement, same(vElement));
      expect(left.staticType, typeProvider.intType);
    }
  }

  test_stringInterpolation_multiLine_emptyBeforeAfter() async {
    addTestFile(r"""
void main() {
  var v = 42;
  '''$v''';
}
""");
    await resolveTestFile();
    expect(result.errors, isEmpty);
  }

  test_super() async {
    String content = r'''
class A {
  void method(int p) {}
  int get getter => 0;
  void set setter(int p) {}
  int operator+(int p) => 0;
}
class B extends A {
  void test() {
    method(1);
    super.method(2);
    getter;
    super.getter;
    setter = 3;
    super.setter = 4;
    this + 5;
  }
}
''';
    addTestFile(content);
    await resolveTestFile();

    ClassDeclaration aNode = result.unit.declarations[0];
    ClassDeclaration bNode = result.unit.declarations[1];

    MethodElement methodElement = aNode.members[0].element;
    PropertyAccessorElement getterElement = aNode.members[1].element;
    PropertyAccessorElement setterElement = aNode.members[2].element;
    MethodElement operatorElement = aNode.members[3].element;

    MethodDeclaration testNode = bNode.members[0];
    BlockFunctionBody testBody = testNode.body;
    List<Statement> testStatements = testBody.block.statements;

    // method(1);
    {
      ExpressionStatement statement = testStatements[0];
      MethodInvocation invocation = statement.expression;

      expect(invocation.target, isNull);

      expect(invocation.methodName.staticElement, same(methodElement));
    }

    // super.method(2);
    {
      ExpressionStatement statement = testStatements[1];
      MethodInvocation invocation = statement.expression;

      SuperExpression target = invocation.target;
      expect(target.staticType, bNode.element.type); // raw

      expect(invocation.methodName.staticElement, same(methodElement));
    }

    // getter;
    {
      ExpressionStatement statement = testStatements[2];
      SimpleIdentifier identifier = statement.expression;

      expect(identifier.staticElement, same(getterElement));
      expect(identifier.staticType, same(typeProvider.intType));
    }

    // super.getter;
    {
      ExpressionStatement statement = testStatements[3];
      PropertyAccess propertyAccess = statement.expression;
      expect(propertyAccess.staticType, same(typeProvider.intType));

      SuperExpression target = propertyAccess.target;
      expect(target.staticType, bNode.element.type); // raw

      expect(propertyAccess.propertyName.staticElement, same(getterElement));
      expect(
          propertyAccess.propertyName.staticType, same(typeProvider.intType));
    }

    // setter = 3;
    {
      ExpressionStatement statement = testStatements[4];
      AssignmentExpression assignment = statement.expression;

      SimpleIdentifier identifier = assignment.leftHandSide;
      expect(identifier.staticElement, same(setterElement));
      expect(identifier.staticType, same(typeProvider.intType));
    }

    // this.setter = 4;
    {
      ExpressionStatement statement = testStatements[5];
      AssignmentExpression assignment = statement.expression;

      PropertyAccess propertyAccess = assignment.leftHandSide;

      SuperExpression target = propertyAccess.target;
      expect(target.staticType, bNode.element.type); // raw

      expect(propertyAccess.propertyName.staticElement, same(setterElement));
      expect(
          propertyAccess.propertyName.staticType, same(typeProvider.intType));
    }

    // super + 5;
    {
      ExpressionStatement statement = testStatements[6];
      BinaryExpression binary = statement.expression;

      ThisExpression target = binary.leftOperand;
      expect(target.staticType, bNode.element.type); // raw

      expect(binary.staticElement, same(operatorElement));
      expect(binary.staticType, typeProvider.intType);
    }
  }

  test_this() async {
    String content = r'''
class A {
  void method(int p) {}
  int get getter => 0;
  void set setter(int p) {}
  int operator+(int p) => 0;
  void test() {
    method(1);
    this.method(2);
    getter;
    this.getter;
    setter = 3;
    this.setter = 4;
    this + 5;
  }
}
''';
    addTestFile(content);
    await resolveTestFile();

    ClassDeclaration aNode = result.unit.declarations[0];

    MethodElement methodElement = aNode.members[0].element;
    PropertyAccessorElement getterElement = aNode.members[1].element;
    PropertyAccessorElement setterElement = aNode.members[2].element;
    MethodElement operatorElement = aNode.members[3].element;

    MethodDeclaration testNode = aNode.members[4];
    BlockFunctionBody testBody = testNode.body;
    List<Statement> testStatements = testBody.block.statements;

    // method(1);
    {
      ExpressionStatement statement = testStatements[0];
      MethodInvocation invocation = statement.expression;

      expect(invocation.target, isNull);

      expect(invocation.methodName.staticElement, same(methodElement));
    }

    // this.method(2);
    {
      ExpressionStatement statement = testStatements[1];
      MethodInvocation invocation = statement.expression;

      ThisExpression target = invocation.target;
      expect(target.staticType, aNode.element.type); // raw

      expect(invocation.methodName.staticElement, same(methodElement));
    }

    // getter;
    {
      ExpressionStatement statement = testStatements[2];
      SimpleIdentifier identifier = statement.expression;

      expect(identifier.staticElement, same(getterElement));
      expect(identifier.staticType, typeProvider.intType);
    }

    // this.getter;
    {
      ExpressionStatement statement = testStatements[3];
      PropertyAccess propertyAccess = statement.expression;
      expect(propertyAccess.staticType, typeProvider.intType);

      ThisExpression target = propertyAccess.target;
      expect(target.staticType, aNode.element.type); // raw

      expect(propertyAccess.propertyName.staticElement, same(getterElement));
      expect(propertyAccess.propertyName.staticType, typeProvider.intType);
    }

    // setter = 3;
    {
      ExpressionStatement statement = testStatements[4];
      AssignmentExpression assignment = statement.expression;

      SimpleIdentifier identifier = assignment.leftHandSide;
      expect(identifier.staticElement, same(setterElement));
      expect(identifier.staticType, typeProvider.intType);
    }

    // this.setter = 4;
    {
      ExpressionStatement statement = testStatements[5];
      AssignmentExpression assignment = statement.expression;

      PropertyAccess propertyAccess = assignment.leftHandSide;

      ThisExpression target = propertyAccess.target;
      expect(target.staticType, aNode.element.type); // raw

      expect(propertyAccess.propertyName.staticElement, same(setterElement));
      expect(propertyAccess.propertyName.staticType, typeProvider.intType);
    }

    // this + 5;
    {
      ExpressionStatement statement = testStatements[6];
      BinaryExpression binary = statement.expression;

      ThisExpression target = binary.leftOperand;
      expect(target.staticType, aNode.element.type); // raw

      expect(binary.staticElement, same(operatorElement));
      expect(binary.staticType, typeProvider.intType);
    }
  }

  test_top_class() async {
    String content = r'''
class A<T> {}
class B<T> {}
class C<T> {}
class D extends A<bool> with B<int> implements C<double> {}
''';
    addTestFile(content);
    await resolveTestFile();

    ClassDeclaration aNode = result.unit.declarations[0];
    ClassElement aElement = aNode.element;

    ClassDeclaration bNode = result.unit.declarations[1];
    ClassElement bElement = bNode.element;

    ClassDeclaration cNode = result.unit.declarations[2];
    ClassElement cElement = cNode.element;

    ClassDeclaration dNode = result.unit.declarations[3];
    Element dElement = dNode.element;

    SimpleIdentifier dName = dNode.name;
    expect(dName.staticElement, same(dElement));
    expect(dName.staticType, typeProvider.typeType);

    {
      var aRawType = aElement.type;
      var expectedType = aRawType.instantiate([typeProvider.boolType]);

      TypeName superClass = dNode.extendsClause.superclass;
      expect(superClass.type, expectedType);

      SimpleIdentifier identifier = superClass.name;
      expect(identifier.staticElement, aElement);
      expect(identifier.staticType, expectedType);
    }

    {
      var bRawType = bElement.type;
      var expectedType = bRawType.instantiate([typeProvider.intType]);

      TypeName mixinType = dNode.withClause.mixinTypes[0];
      expect(mixinType.type, expectedType);

      SimpleIdentifier identifier = mixinType.name;
      expect(identifier.staticElement, bElement);
      expect(identifier.staticType, expectedType);
    }

    {
      var cRawType = cElement.type;
      var expectedType = cRawType.instantiate([typeProvider.doubleType]);

      TypeName implementedType = dNode.implementsClause.interfaces[0];
      expect(implementedType.type, expectedType);

      SimpleIdentifier identifier = implementedType.name;
      expect(identifier.staticElement, cElement);
      expect(identifier.staticType, expectedType);
    }
  }

  test_top_class_constructor_parameter_defaultValue() async {
    String content = r'''
class C {
  double f;
  C([int a: 1 + 2]) : f = 3.4;
}
''';
    addTestFile(content);
    await resolveTestFile();

    ClassDeclaration cNode = result.unit.declarations[0];
    ClassElement cElement = cNode.element;

    ConstructorDeclaration constructorNode = cNode.members[1];

    DefaultFormalParameter aNode = constructorNode.parameters.parameters[0];
    _assertDefaultParameter(aNode, cElement.unnamedConstructor.parameters[0],
        name: 'a',
        offset: 31,
        kind: ParameterKind.POSITIONAL,
        type: typeProvider.intType);

    BinaryExpression binary = aNode.defaultValue;
    expect(binary.staticElement, isNotNull);
    expect(binary.staticType, typeProvider.intType);
    expect(binary.leftOperand.staticType, typeProvider.intType);
    expect(binary.rightOperand.staticType, typeProvider.intType);
  }

  test_top_classTypeAlias() async {
    String content = r'''
class A<T> {}
class B<T> {}
class C<T> {}
class D = A<bool> with B<int> implements C<double>;
''';
    addTestFile(content);
    await resolveTestFile();

    ClassDeclaration aNode = result.unit.declarations[0];
    ClassElement aElement = aNode.element;

    ClassDeclaration bNode = result.unit.declarations[1];
    ClassElement bElement = bNode.element;

    ClassDeclaration cNode = result.unit.declarations[2];
    ClassElement cElement = cNode.element;

    ClassTypeAlias dNode = result.unit.declarations[3];
    Element dElement = dNode.element;

    SimpleIdentifier dName = dNode.name;
    expect(dName.staticElement, same(dElement));
    expect(dName.staticType, typeProvider.typeType);

    {
      var aRawType = aElement.type;
      var expectedType = aRawType.instantiate([typeProvider.boolType]);

      TypeName superClass = dNode.superclass;
      expect(superClass.type, expectedType);

      SimpleIdentifier identifier = superClass.name;
      expect(identifier.staticElement, same(aElement));
      expect(identifier.staticType, expectedType);
    }

    {
      var bRawType = bElement.type;
      var expectedType = bRawType.instantiate([typeProvider.intType]);

      TypeName mixinType = dNode.withClause.mixinTypes[0];
      expect(mixinType.type, expectedType);

      SimpleIdentifier identifier = mixinType.name;
      expect(identifier.staticElement, same(bElement));
      expect(identifier.staticType, expectedType);
    }

    {
      var cRawType = cElement.type;
      var expectedType = cRawType.instantiate([typeProvider.doubleType]);

      TypeName interfaceType = dNode.implementsClause.interfaces[0];
      expect(interfaceType.type, expectedType);

      SimpleIdentifier identifier = interfaceType.name;
      expect(identifier.staticElement, same(cElement));
      expect(identifier.staticType, expectedType);
    }
  }

  test_top_enum() async {
    String content = r'''
enum MyEnum {
  A, B
}
''';
    addTestFile(content);
    await resolveTestFile();

    EnumDeclaration enumNode = result.unit.declarations[0];
    ClassElement enumElement = enumNode.element;

    SimpleIdentifier dName = enumNode.name;
    expect(dName.staticElement, same(enumElement));
    if (useCFE) {
      expect(dName.staticType, typeProvider.typeType);
    }

    {
      var aElement = enumElement.getField('A');
      var aNode = enumNode.constants[0];
      expect(aNode.element, same(aElement));
      expect(aNode.name.staticElement, same(aElement));
      expect(aNode.name.staticType, same(enumElement.type));
    }

    {
      var bElement = enumElement.getField('B');
      var bNode = enumNode.constants[1];
      expect(bNode.element, same(bElement));
      expect(bNode.name.staticElement, same(bElement));
      expect(bNode.name.staticType, same(enumElement.type));
    }
  }

  test_top_executables_class() async {
    String content = r'''
class C {
  C(int p);
  C.named(int p);

  int publicMethod(double p) => 0;
  int get publicGetter => 0;
  void set publicSetter(double p) {}
}
''';
    addTestFile(content);

    await resolveTestFile();
    expect(result.path, testFile);

    InterfaceType typeType = typeProvider.typeType;
    InterfaceType doubleType = typeProvider.doubleType;
    InterfaceType intType = typeProvider.intType;
    ClassElement doubleElement = doubleType.element;
    ClassElement intElement = intType.element;

    ClassDeclaration cNode = result.unit.declarations[0];
    ClassElement cElement = cNode.element;

    // The class name identifier.
    expect(cNode.name.staticElement, same(cElement));
    expect(cNode.name.staticType, typeType);

    // unnamed constructor
    {
      ConstructorDeclaration node = cNode.members[0];
      expect(node.element, isNotNull);
      expect(node.element.type.toString(), '(int) → C');
      expect(node.returnType.staticElement, same(cElement));
      expect(node.returnType.staticType, typeType);
      expect(node.name, isNull);
    }

    // named constructor
    {
      ConstructorDeclaration node = cNode.members[1];
      expect(node.element, isNotNull);
      expect(node.element.type.toString(), '(int) → C');
      expect(node.returnType.staticElement, same(cElement));
      expect(node.returnType.staticType, typeType);
      expect(node.name.staticElement, same(node.element));
      expect(node.name.staticType.toString(), '(int) → C');
    }

    // publicMethod()
    {
      MethodDeclaration node = cNode.members[2];
      expect(node.element, isNotNull);
      expect(node.element.type.toString(), '(double) → int');

      // method return type
      TypeName returnType = node.returnType;
      SimpleIdentifier returnTypeName = returnType.name;
      expect(returnType.type, intType);
      expect(returnTypeName.staticElement, intElement);
      expect(returnTypeName.staticType, intType);

      // method name
      expect(node.name.staticElement, same(node.element));
      expect(node.name.staticType, same(node.element.type));

      // method parameter
      {
        SimpleFormalParameter pNode = node.parameters.parameters[0];
        expect(pNode.element, isNotNull);
        expect(pNode.element.type, doubleType);

        TypeName pType = pNode.type;
        expect(pType.name.staticElement, doubleElement);
        expect(pType.name.staticType, doubleType);

        expect(pNode.identifier.staticElement, pNode.element);
        expect(pNode.identifier.staticType, doubleType);
      }
    }

    // publicGetter()
    {
      MethodDeclaration node = cNode.members[3];
      expect(node.element, isNotNull);
      expect(node.element.type.toString(), '() → int');

      // getter return type
      TypeName returnType = node.returnType;
      SimpleIdentifier returnTypeName = returnType.name;
      expect(returnType.type, intType);
      expect(returnTypeName.staticElement, intElement);
      expect(returnTypeName.staticType, intType);

      // getter name
      expect(node.name.staticElement, same(node.element));
      expect(node.name.staticType, intType);
    }

    // publicSetter()
    {
      MethodDeclaration node = cNode.members[4];
      expect(node.element, isNotNull);
      expect(node.element.type.toString(), '(double) → void');

      // setter return type
      TypeName returnType = node.returnType;
      SimpleIdentifier returnTypeName = returnType.name;
      expect(returnType.type, VoidTypeImpl.instance);
      expect(returnTypeName.staticElement, isNull);
      expect(returnTypeName.staticType, VoidTypeImpl.instance);

      // setter name
      expect(node.name.staticElement, same(node.element));
      expect(node.name.staticType, doubleType);

      // setter parameter
      {
        SimpleFormalParameter pNode = node.parameters.parameters[0];
        expect(pNode.element, isNotNull);
        expect(pNode.element.type, doubleType);

        TypeName pType = pNode.type;
        expect(pType.name.staticElement, doubleElement);
        expect(pType.name.staticType, doubleType);

        expect(pNode.identifier.staticElement, pNode.element);
        expect(pNode.identifier.staticType, doubleType);
      }
    }
  }

  test_top_executables_top() async {
    String content = r'''
int topFunction(double p) => 0;
int get topGetter => 0;
void set topSetter(double p) {}
''';
    addTestFile(content);

    await resolveTestFile();
    expect(result.path, testFile);

    InterfaceType doubleType = typeProvider.doubleType;
    InterfaceType intType = typeProvider.intType;
    ClassElement doubleElement = doubleType.element;
    ClassElement intElement = intType.element;

    // topFunction()
    {
      FunctionDeclaration node = result.unit.declarations[0];
      expect(node.element, isNotNull);
      expect(node.element.type.toString(), '(double) → int');

      // function return type
      TypeName returnType = node.returnType;
      SimpleIdentifier returnTypeName = returnType.name;
      expect(returnType.type, intType);
      expect(returnTypeName.staticElement, intElement);
      expect(returnTypeName.staticType, intType);

      // function name
      expect(node.name.staticElement, same(node.element));
      expect(node.name.staticType, same(node.element.type));

      // function parameter
      {
        SimpleFormalParameter pNode =
            node.functionExpression.parameters.parameters[0];
        expect(pNode.element, isNotNull);
        expect(pNode.element.type, doubleType);

        TypeName pType = pNode.type;
        expect(pType.name.staticElement, doubleElement);
        expect(pType.name.staticType, doubleType);

        expect(pNode.identifier.staticElement, pNode.element);
        expect(pNode.identifier.staticType, doubleType);
      }
    }

    // topGetter()
    {
      FunctionDeclaration node = result.unit.declarations[1];
      expect(node.element, isNotNull);
      expect(node.element.type.toString(), '() → int');

      // getter return type
      TypeName returnType = node.returnType;
      SimpleIdentifier returnTypeName = returnType.name;
      expect(returnType.type, intType);
      expect(returnTypeName.staticElement, intElement);
      expect(returnTypeName.staticType, intType);

      // getter name
      expect(node.name.staticElement, same(node.element));
      expect(node.name.staticType, intType);
    }

    // topSetter()
    {
      FunctionDeclaration node = result.unit.declarations[2];
      expect(node.element, isNotNull);
      expect(node.element.type.toString(), '(double) → void');

      // setter return type
      TypeName returnType = node.returnType;
      SimpleIdentifier returnTypeName = returnType.name;
      expect(returnType.type, VoidTypeImpl.instance);
      expect(returnTypeName.staticElement, isNull);
      expect(returnTypeName.staticType, VoidTypeImpl.instance);

      // setter name
      expect(node.name.staticElement, same(node.element));
      expect(node.name.staticType, doubleType);

      // setter parameter
      {
        SimpleFormalParameter pNode =
            node.functionExpression.parameters.parameters[0];
        expect(pNode.element, isNotNull);
        expect(pNode.element.type, doubleType);

        TypeName pType = pNode.type;
        expect(pType.name.staticElement, doubleElement);
        expect(pType.name.staticType, doubleType);

        expect(pNode.identifier.staticElement, pNode.element);
        expect(pNode.identifier.staticType, doubleType);
      }
    }
  }

  test_top_field_class() async {
    String content = r'''
class C<T> {
  var a = 1;
  T b;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    CompilationUnitElement unitElement = unit.element;
    var typeProvider = unitElement.context.typeProvider;

    ClassDeclaration cNode = unit.declarations[0];
    ClassElement cElement = cNode.element;
    TypeParameterElement tElement = cElement.typeParameters[0];
    expect(cElement, same(unitElement.types[0]));

    {
      FieldElement aElement = cElement.getField('a');
      FieldDeclaration aDeclaration = cNode.members[0];
      VariableDeclaration aNode = aDeclaration.fields.variables[0];
      expect(aNode.element, same(aElement));
      expect(aElement.type, typeProvider.intType);
      expect(aNode.name.staticElement, same(aElement));
      expect(aNode.name.staticType, same(aElement.type));

      Expression aValue = aNode.initializer;
      expect(aValue.staticType, typeProvider.intType);
    }

    {
      FieldElement bElement = cElement.getField('b');
      FieldDeclaration bDeclaration = cNode.members[1];

      TypeName typeName = bDeclaration.fields.type;
      SimpleIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, same(tElement));
      expect(typeIdentifier.staticType, same(tElement.type));

      VariableDeclaration bNode = bDeclaration.fields.variables[0];
      expect(bNode.element, same(bElement));
      expect(bElement.type, tElement.type);
      expect(bNode.name.staticElement, same(bElement));
      expect(bNode.name.staticType, same(bElement.type));
    }
  }

  test_top_field_class_multiple() async {
    String content = r'''
class C {
  var a = 1, b = 2.3;
}
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    CompilationUnitElement unitElement = unit.element;
    var typeProvider = unitElement.context.typeProvider;

    ClassDeclaration cNode = unit.declarations[0];
    ClassElement cElement = cNode.element;

    FieldDeclaration fieldDeclaration = cNode.members[0];

    {
      FieldElement aElement = cElement.getField('a');

      VariableDeclaration aNode = fieldDeclaration.fields.variables[0];
      expect(aNode.element, same(aElement));
      expect(aElement.type, typeProvider.intType);

      expect(aNode.name.staticElement, same(aElement));
      expect(aNode.name.staticType, same(aElement.type));

      Expression aValue = aNode.initializer;
      expect(aValue.staticType, typeProvider.intType);
    }

    {
      FieldElement bElement = cElement.getField('b');

      VariableDeclaration bNode = fieldDeclaration.fields.variables[1];
      expect(bNode.element, same(bElement));
      expect(bElement.type, typeProvider.doubleType);

      expect(bNode.name.staticElement, same(bElement));
      expect(bNode.name.staticType, same(bElement.type));

      Expression aValue = bNode.initializer;
      expect(aValue.staticType, typeProvider.doubleType);
    }
  }

  test_top_field_top() async {
    String content = r'''
var a = 1;
double b = 2.3;
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    CompilationUnitElement unitElement = unit.element;
    var typeProvider = unitElement.context.typeProvider;

    {
      TopLevelVariableDeclaration aDeclaration = unit.declarations[0];
      VariableDeclaration aNode = aDeclaration.variables.variables[0];
      TopLevelVariableElement aElement = aNode.element;
      expect(aElement, same(unitElement.topLevelVariables[0]));
      expect(aElement.type, typeProvider.intType);
      expect(aNode.name.staticElement, same(aElement));
      expect(aNode.name.staticType, same(aElement.type));

      Expression aValue = aNode.initializer;
      expect(aValue.staticType, typeProvider.intType);
    }

    {
      TopLevelVariableDeclaration bDeclaration = unit.declarations[1];

      VariableDeclaration bNode = bDeclaration.variables.variables[0];
      TopLevelVariableElement bElement = bNode.element;
      expect(bElement, same(unitElement.topLevelVariables[1]));
      expect(bElement.type, typeProvider.doubleType);

      TypeName typeName = bDeclaration.variables.type;
      _assertTypeNameSimple(typeName, typeProvider.doubleType);

      expect(bNode.name.staticElement, same(bElement));
      expect(bNode.name.staticType, same(bElement.type));

      Expression aValue = bNode.initializer;
      expect(aValue.staticType, typeProvider.doubleType);
    }
  }

  test_top_field_top_multiple() async {
    String content = r'''
var a = 1, b = 2.3;
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    CompilationUnitElement unitElement = unit.element;
    var typeProvider = unitElement.context.typeProvider;

    TopLevelVariableDeclaration variableDeclaration = unit.declarations[0];
    expect(variableDeclaration.variables.type, isNull);

    {
      VariableDeclaration aNode = variableDeclaration.variables.variables[0];
      TopLevelVariableElement aElement = aNode.element;
      expect(aElement, same(unitElement.topLevelVariables[0]));
      expect(aElement.type, typeProvider.intType);

      expect(aNode.name.staticElement, same(aElement));
      expect(aNode.name.staticType, aElement.type);

      Expression aValue = aNode.initializer;
      expect(aValue.staticType, typeProvider.intType);
    }

    {
      VariableDeclaration bNode = variableDeclaration.variables.variables[1];
      TopLevelVariableElement bElement = bNode.element;
      expect(bElement, same(unitElement.topLevelVariables[1]));
      expect(bElement.type, typeProvider.doubleType);

      expect(bNode.name.staticElement, same(bElement));
      expect(bNode.name.staticType, bElement.type);

      Expression aValue = bNode.initializer;
      expect(aValue.staticType, typeProvider.doubleType);
    }
  }

  test_top_function_namedParameters() async {
    addTestFile(r'''
double f(int a, {String b, bool c: 1 == 2}) {}
void main() {
  f(1, b: '2', c: true);
}
''');
    String fTypeString = '(int, {b: String, c: bool}) → double';

    await resolveTestFile();
    FunctionDeclaration fDeclaration = result.unit.declarations[0];
    FunctionElement fElement = fDeclaration.element;

    InterfaceType doubleType = typeProvider.doubleType;

    expect(fElement, isNotNull);
    expect(fElement.type.toString(), fTypeString);

    expect(fDeclaration.name.staticElement, same(fElement));
    expect(fDeclaration.name.staticType, fElement.type);

    TypeName fReturnTypeNode = fDeclaration.returnType;
    expect(fReturnTypeNode.name.staticElement, same(doubleType.element));
    expect(fReturnTypeNode.type, doubleType);
    //
    // Validate the parameters at the declaration site.
    //
    List<ParameterElement> elements = fElement.parameters;
    expect(elements, hasLength(3));

    List<FormalParameter> nodes =
        fDeclaration.functionExpression.parameters.parameters;
    expect(nodes, hasLength(3));

    _assertSimpleParameter(nodes[0], elements[0],
        name: 'a',
        offset: 13,
        kind: ParameterKind.REQUIRED,
        type: typeProvider.intType);

    DefaultFormalParameter bNode = nodes[1];
    _assertDefaultParameter(bNode, elements[1],
        name: 'b',
        offset: 24,
        kind: ParameterKind.NAMED,
        type: typeProvider.stringType);
    expect(bNode.defaultValue, isNull);

    DefaultFormalParameter cNode = nodes[2];
    _assertDefaultParameter(cNode, elements[2],
        name: 'c',
        offset: 32,
        kind: ParameterKind.NAMED,
        type: typeProvider.boolType);
    {
      BinaryExpression defaultValue = cNode.defaultValue;
      expect(defaultValue.staticElement, isNotNull);
      expect(defaultValue.staticType, typeProvider.boolType);
    }

    //
    // Validate the arguments at the call site.
    //
    FunctionDeclaration mainDeclaration = result.unit.declarations[1];
    BlockFunctionBody body = mainDeclaration.functionExpression.body;
    ExpressionStatement statement = body.block.statements[0];
    MethodInvocation invocation = statement.expression;
    List<Expression> arguments = invocation.argumentList.arguments;

    _assertArgumentToParameter(arguments[0], fElement.parameters[0]);
    _assertArgumentToParameter(arguments[1], fElement.parameters[1]);
    _assertArgumentToParameter(arguments[2], fElement.parameters[2]);
  }

  test_top_functionTypeAlias() async {
    String content = r'''
typedef int F<T>(bool a, T b);
''';
    addTestFile(content);

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    CompilationUnitElement unitElement = unit.element;
    var typeProvider = unitElement.context.typeProvider;

    FunctionTypeAlias alias = unit.declarations[0];
    FunctionTypeAliasElement aliasElement = alias.element;
    expect(aliasElement, same(unitElement.functionTypeAliases[0]));
    expect(aliasElement.returnType, typeProvider.intType);

    _assertTypeNameSimple(alias.returnType, typeProvider.intType);

    _assertSimpleParameter(
        alias.parameters.parameters[0], aliasElement.parameters[0],
        name: 'a',
        offset: 22,
        kind: ParameterKind.REQUIRED,
        type: typeProvider.boolType);

    _assertSimpleParameter(
        alias.parameters.parameters[1], aliasElement.parameters[1],
        name: 'b',
        offset: 27,
        kind: ParameterKind.REQUIRED,
        type: aliasElement.typeParameters[0].type);
  }

  test_top_typeParameter() async {
    String content = r'''
class A {}
class C<T extends A, U extends List<A>, V> {}
''';
    addTestFile(content);
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    CompilationUnitElement unitElement = unit.element;
    var typeProvider = unitElement.context.typeProvider;

    ClassDeclaration aNode = unit.declarations[0];
    ClassElement aElement = aNode.element;
    expect(aElement, same(unitElement.types[0]));

    ClassDeclaration cNode = unit.declarations[1];
    ClassElement cElement = cNode.element;
    expect(cElement, same(unitElement.types[1]));

    {
      TypeParameter tNode = cNode.typeParameters.typeParameters[0];
      expect(tNode.element, same(cElement.typeParameters[0]));

      TypeName bound = tNode.bound;
      expect(bound.type, aElement.type);

      SimpleIdentifier boundIdentifier = bound.name;
      expect(boundIdentifier.staticElement, same(aElement));
      expect(boundIdentifier.staticType, aElement.type);
    }

    {
      var listElement = typeProvider.listType.element;
      var listOfA = typeProvider.listType.instantiate([aElement.type]);

      TypeParameter uNode = cNode.typeParameters.typeParameters[1];
      expect(uNode.element, same(cElement.typeParameters[1]));

      TypeName bound = uNode.bound;
      expect(bound.type, listOfA);

      SimpleIdentifier listIdentifier = bound.name;
      expect(listIdentifier.staticElement, same(listElement));
      expect(listIdentifier.staticType, listOfA);

      TypeName aTypeName = bound.typeArguments.arguments[0];
      expect(aTypeName.type, aElement.type);

      SimpleIdentifier aIdentifier = aTypeName.name;
      expect(aIdentifier.staticElement, same(aElement));
      expect(aIdentifier.staticType, aElement.type);
    }

    {
      TypeParameter vNode = cNode.typeParameters.typeParameters[2];
      expect(vNode.element, same(cElement.typeParameters[2]));
      expect(vNode.bound, isNull);
    }
  }

  test_tryCatch() async {
    addTestFile(r'''
void main() {
  try {} catch (e, st) {
    e;
    st;
  }
  try {} on int catch (e, st) {
    e;
    st;
  }
  try {} catch (e) {
    e;
  }
  try {} on int catch (e) {
    e;
  }
  try {} on int {}
}
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    List<Statement> statements = _getMainStatements(result);

    // catch (e, st)
    {
      TryStatement statement = statements[0];
      CatchClause catchClause = statement.catchClauses[0];
      expect(catchClause.exceptionType, isNull);

      SimpleIdentifier exceptionNode = catchClause.exceptionParameter;
      LocalVariableElement exceptionElement = exceptionNode.staticElement;
      expect(exceptionElement.type, DynamicTypeImpl.instance);

      SimpleIdentifier stackNode = catchClause.stackTraceParameter;
      LocalVariableElement stackElement = stackNode.staticElement;
      expect(stackElement.type, typeProvider.stackTraceType);

      List<Statement> catchStatements = catchClause.body.statements;

      ExpressionStatement exceptionStatement = catchStatements[0];
      SimpleIdentifier exceptionIdentifier = exceptionStatement.expression;
      expect(exceptionIdentifier.staticElement, same(exceptionElement));
      expect(exceptionIdentifier.staticType, DynamicTypeImpl.instance);

      ExpressionStatement stackStatement = catchStatements[1];
      SimpleIdentifier stackIdentifier = stackStatement.expression;
      expect(stackIdentifier.staticElement, same(stackElement));
      expect(stackIdentifier.staticType, typeProvider.stackTraceType);
    }

    // on int catch (e, st)
    {
      TryStatement statement = statements[1];
      CatchClause catchClause = statement.catchClauses[0];
      _assertTypeNameSimple(catchClause.exceptionType, typeProvider.intType);

      SimpleIdentifier exceptionNode = catchClause.exceptionParameter;
      LocalVariableElement exceptionElement = exceptionNode.staticElement;
      expect(exceptionElement.type, typeProvider.intType);

      SimpleIdentifier stackNode = catchClause.stackTraceParameter;
      LocalVariableElement stackElement = stackNode.staticElement;
      expect(stackElement.type, typeProvider.stackTraceType);

      List<Statement> catchStatements = catchClause.body.statements;

      ExpressionStatement exceptionStatement = catchStatements[0];
      SimpleIdentifier exceptionIdentifier = exceptionStatement.expression;
      expect(exceptionIdentifier.staticElement, same(exceptionElement));
      expect(exceptionIdentifier.staticType, typeProvider.intType);

      ExpressionStatement stackStatement = catchStatements[1];
      SimpleIdentifier stackIdentifier = stackStatement.expression;
      expect(stackIdentifier.staticElement, same(stackElement));
      expect(stackIdentifier.staticType, typeProvider.stackTraceType);
    }

    // catch (e)
    {
      TryStatement statement = statements[2];
      CatchClause catchClause = statement.catchClauses[0];
      expect(catchClause.exceptionType, isNull);
      expect(catchClause.stackTraceParameter, isNull);

      SimpleIdentifier exceptionNode = catchClause.exceptionParameter;
      LocalVariableElement exceptionElement = exceptionNode.staticElement;
      expect(exceptionElement.type, DynamicTypeImpl.instance);
    }

    // on int catch (e)
    {
      TryStatement statement = statements[3];
      CatchClause catchClause = statement.catchClauses[0];
      _assertTypeNameSimple(catchClause.exceptionType, typeProvider.intType);
      expect(catchClause.stackTraceParameter, isNull);

      SimpleIdentifier exceptionNode = catchClause.exceptionParameter;
      LocalVariableElement exceptionElement = exceptionNode.staticElement;
      expect(exceptionElement.type, typeProvider.intType);
    }

    // on int catch (e)
    {
      TryStatement statement = statements[4];
      CatchClause catchClause = statement.catchClauses[0];
      _assertTypeNameSimple(catchClause.exceptionType, typeProvider.intType);
      expect(catchClause.exceptionParameter, isNull);
      expect(catchClause.stackTraceParameter, isNull);
    }
  }

  test_type_functionTypeAlias() async {
    addTestFile(r'''
typedef T F<T>(bool a);
class C {
  F<int> f;
}
''');

    await resolveTestFile();
    CompilationUnit unit = result.unit;
    CompilationUnitElement unitElement = unit.element;
    var typeProvider = unitElement.context.typeProvider;

    FunctionTypeAlias alias = unit.declarations[0];
    GenericTypeAliasElement aliasElement = alias.element;
    FunctionType aliasType = aliasElement.type;

    ClassDeclaration cNode = unit.declarations[1];

    FieldDeclaration fDeclaration = cNode.members[0];
    FunctionType instantiatedAliasType =
        aliasType.instantiate([typeProvider.intType]);

    TypeName typeName = fDeclaration.fields.type;
    expect(typeName.type, instantiatedAliasType);

    SimpleIdentifier typeIdentifier = typeName.name;
    expect(typeIdentifier.staticElement, same(aliasElement));
    expect(typeIdentifier.staticType, instantiatedAliasType);

    List<TypeAnnotation> typeArguments = typeName.typeArguments.arguments;
    expect(typeArguments, hasLength(1));
    _assertTypeNameSimple(typeArguments[0], typeProvider.intType);
  }

  test_typeAnnotation_prefixed() async {
    var a = _p('/test/lib/a.dart');
    var b = _p('/test/lib/b.dart');
    var c = _p('/test/lib/c.dart');
    provider.newFile(a, 'class A {}');
    provider.newFile(b, "export 'a.dart';");
    provider.newFile(c, "export 'a.dart';");
    addTestFile(r'''
import 'b.dart' as b;
import 'c.dart' as c;
b.A a1;
c.A a2;
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;

    ImportElement bImport = unit.element.library.imports[0];
    ImportElement cImport = unit.element.library.imports[1];

    LibraryElement bLibrary = bImport.importedLibrary;
    LibraryElement aLibrary = bLibrary.exports[0].exportedLibrary;
    ClassElement aClass = aLibrary.getType('A');

    {
      TopLevelVariableDeclaration declaration = unit.declarations[0];
      TypeName typeName = declaration.variables.type;

      PrefixedIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, aClass);

      expect(typeIdentifier.prefix.name, 'b');
      expect(typeIdentifier.prefix.staticElement, same(bImport.prefix));

      expect(typeIdentifier.identifier.staticElement, aClass);
    }

    {
      TopLevelVariableDeclaration declaration = unit.declarations[1];
      TypeName typeName = declaration.variables.type;

      PrefixedIdentifier typeIdentifier = typeName.name;
      expect(typeIdentifier.staticElement, aClass);

      expect(typeIdentifier.prefix.name, 'c');
      expect(typeIdentifier.prefix.staticElement, same(cImport.prefix));

      expect(typeIdentifier.identifier.staticElement, aClass);
    }
  }

  test_typeLiteral() async {
    addTestFile(r'''
void main() {
  int;
  F;
}
typedef void F(int p);
''');
    await resolveTestFile();
    CompilationUnit unit = result.unit;
    var typeProvider = unit.element.context.typeProvider;

    FunctionTypeAlias fNode = unit.declarations[1];
    FunctionTypeAliasElement fElement = fNode.element;

    var statements = _getMainStatements(result);

    {
      ExpressionStatement statement = statements[0];
      SimpleIdentifier identifier = statement.expression;
      expect(identifier.staticElement, same(typeProvider.intType.element));
      expect(identifier.staticType, typeProvider.typeType);
    }

    {
      ExpressionStatement statement = statements[1];
      SimpleIdentifier identifier = statement.expression;
      expect(identifier.staticElement, same(fElement));
      expect(identifier.staticType, typeProvider.typeType);
    }
  }

  test_typeParameter() async {
    addTestFile(r'''
class C<T> {
  get t => T;
}
''');
    await resolveTestFile();

    var identifier = findNode.simple('T;');
    assertElement(identifier, findElement.typeParameter('T'));
    assertType(identifier, 'Type');
  }

  test_unresolved_assignment_left_identifier_compound() async {
    addTestFile(r'''
int b;
main() {
  a += b;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var assignment = findNode.assignment('a += b');
    assertElementNull(assignment);
    assertTypeDynamic(assignment);

    assertElementNull(assignment.leftHandSide);
    assertTypeDynamic(assignment.leftHandSide);

    assertElement(assignment.rightHandSide, findElement.topGet('b'));
    assertType(assignment.rightHandSide, 'int');
  }

  test_unresolved_assignment_left_identifier_simple() async {
    addTestFile(r'''
int b;
main() {
  a = b;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var assignment = findNode.assignment('a = b');
    assertElementNull(assignment);
    if (useCFE) {
      assertType(assignment, 'int');
    }

    assertElementNull(assignment.leftHandSide);
    assertTypeDynamic(assignment.leftHandSide);

    assertElement(assignment.rightHandSide, findElement.topGet('b'));
    assertType(assignment.rightHandSide, 'int');
  }

  test_unresolved_assignment_left_indexed1_simple() async {
    addTestFile(r'''
int c;
main() {
  a[b] = c;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var assignment = findNode.assignment('a[b] = c');
    assertElementNull(assignment);
    if (useCFE) {
      assertType(assignment, 'int');
    }

    IndexExpression indexed = assignment.leftHandSide;
    assertElementNull(indexed);
    assertTypeDynamic(indexed);

    assertElementNull(indexed.target);
    assertTypeDynamic(indexed.target);

    assertElementNull(indexed.index);
    assertTypeDynamic(indexed.index);

    assertElement(assignment.rightHandSide, findElement.topGet('c'));
    assertType(assignment.rightHandSide, 'int');
  }

  test_unresolved_assignment_left_indexed2_simple() async {
    addTestFile(r'''
A a;
int c;
main() {
  a[b] = c;
}
class A {}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var assignment = findNode.assignment('a[b] = c');
    assertElementNull(assignment);
    if (useCFE) {
      assertType(assignment, 'int');
    }

    IndexExpression indexed = assignment.leftHandSide;
    assertElementNull(indexed);
    assertTypeDynamic(indexed);

    assertElement(indexed.target, findElement.topGet('a'));
    assertType(indexed.target, 'A');

    assertElementNull(indexed.index);
    assertTypeDynamic(indexed.index);

    assertElement(assignment.rightHandSide, findElement.topGet('c'));
    assertType(assignment.rightHandSide, 'int');
  }

  test_unresolved_assignment_left_indexed3_simple() async {
    addTestFile(r'''
A a;
int c;
main() {
  a[b] = c;
}
class A {
  operator[]=(double b) {}
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var assignment = findNode.assignment('a[b] = c');
    assertElementNull(assignment);
    if (useCFE) {
      assertType(assignment, 'int');
    }

    IndexExpression indexed = assignment.leftHandSide;
    assertElement(indexed, findElement.method('[]='));
    assertTypeDynamic(indexed);

    assertElement(indexed.target, findElement.topGet('a'));
    assertType(indexed.target, 'A');

    assertElementNull(indexed.index);
    assertTypeDynamic(indexed.index);

    assertElement(assignment.rightHandSide, findElement.topGet('c'));
    assertType(assignment.rightHandSide, 'int');
  }

  test_unresolved_assignment_left_indexed4_simple() async {
    addTestFile(r'''
double b;
int c;
main() {
  a[b] = c;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var assignment = findNode.assignment('a[b] = c');
    assertElementNull(assignment);
    if (useCFE) {
      assertType(assignment, 'int');
    }

    IndexExpression indexed = assignment.leftHandSide;
    assertElementNull(indexed);
    assertTypeDynamic(indexed);

    assertElementNull(indexed.target);
    assertTypeDynamic(indexed.target);

    assertElement(indexed.index, findElement.topGet('b'));
    assertType(indexed.index, 'double');

    assertElement(assignment.rightHandSide, findElement.topGet('c'));
    assertType(assignment.rightHandSide, 'int');
  }

  test_unresolved_assignment_left_prefixed1_simple() async {
    addTestFile(r'''
int c;
main() {
  a.b = c;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var assignment = findNode.assignment('a.b = c');
    assertElementNull(assignment);
    if (useCFE) {
      assertType(assignment, 'int');
    }

    PrefixedIdentifier prefixed = assignment.leftHandSide;
    assertElementNull(prefixed);
    assertTypeDynamic(prefixed);

    assertElementNull(prefixed.prefix);
    assertTypeDynamic(prefixed.prefix);

    assertElementNull(prefixed.identifier);
    assertTypeDynamic(prefixed.identifier);

    assertElement(assignment.rightHandSide, findElement.topGet('c'));
    assertType(assignment.rightHandSide, 'int');
  }

  test_unresolved_assignment_left_prefixed2_simple() async {
    addTestFile(r'''
class A {}
A a;
int c;
main() {
  a.b = c;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var assignment = findNode.assignment('a.b = c');
    assertElementNull(assignment);
    if (useCFE) {
      assertType(assignment, 'int');
    }

    PrefixedIdentifier prefixed = assignment.leftHandSide;
    assertElementNull(prefixed);
    assertTypeDynamic(prefixed);

    assertElement(prefixed.prefix, findElement.topGet('a'));
    assertType(prefixed.prefix, 'A');

    assertElementNull(prefixed.identifier);
    assertTypeDynamic(prefixed.identifier);

    assertElement(assignment.rightHandSide, findElement.topGet('c'));
    assertType(assignment.rightHandSide, 'int');
  }

  test_unresolved_assignment_left_property1_simple() async {
    addTestFile(r'''
int d;
main() {
  a.b.c = d;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var assignment = findNode.assignment('a.b.c = d');
    assertElementNull(assignment);
    if (useCFE) {
      assertType(assignment, 'int');
    }

    PropertyAccess access = assignment.leftHandSide;
    assertTypeDynamic(access);

    PrefixedIdentifier prefixed = access.target;
    assertElementNull(prefixed);
    assertTypeDynamic(prefixed);

    assertElementNull(prefixed.prefix);
    assertTypeDynamic(prefixed.prefix);

    assertElementNull(prefixed.identifier);
    assertTypeDynamic(prefixed.identifier);

    assertElementNull(access.propertyName);
    assertTypeDynamic(access.propertyName);

    assertElement(assignment.rightHandSide, findElement.topGet('d'));
    assertType(assignment.rightHandSide, 'int');
  }

  test_unresolved_assignment_left_property2_simple() async {
    addTestFile(r'''
A a;
int d;
main() {
  a.b.c = d;
}
class A {}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var assignment = findNode.assignment('a.b.c = d');
    assertElementNull(assignment);
    if (useCFE) {
      assertType(assignment, 'int');
    }

    PropertyAccess access = assignment.leftHandSide;
    assertTypeDynamic(access);

    PrefixedIdentifier prefixed = access.target;
    assertElementNull(prefixed);
    assertTypeDynamic(prefixed);

    assertElement(prefixed.prefix, findElement.topGet('a'));
    assertType(prefixed.prefix, 'A');

    assertElementNull(prefixed.identifier);
    assertTypeDynamic(prefixed.identifier);

    assertElementNull(access.propertyName);
    assertTypeDynamic(access.propertyName);

    assertElement(assignment.rightHandSide, findElement.topGet('d'));
    assertType(assignment.rightHandSide, 'int');
  }

  test_unresolved_assignment_left_property3_simple() async {
    addTestFile(r'''
A a;
int d;
main() {
  a.b.c = d;
}
class A { B b; }
class B {}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);
    var bElement = findElement.field('b');

    var assignment = findNode.assignment('a.b.c = d');
    assertElementNull(assignment);
    if (useCFE) {
      assertType(assignment, 'int');
    }

    PropertyAccess access = assignment.leftHandSide;
    assertTypeDynamic(access);

    PrefixedIdentifier prefixed = access.target;
    assertElement(prefixed, bElement.getter);
    assertType(prefixed, 'B');

    assertElement(prefixed.prefix, findElement.topGet('a'));
    assertType(prefixed.prefix, 'A');

    assertElement(prefixed.identifier, bElement.getter);
    assertType(prefixed.identifier, 'B');

    assertElementNull(access.propertyName);
    assertTypeDynamic(access.propertyName);

    assertElement(assignment.rightHandSide, findElement.topGet('d'));
    assertType(assignment.rightHandSide, 'int');
  }

  test_unresolved_instanceCreation_name_11() async {
    addTestFile(r'''
int arg1, arg2;
main() {
  new Foo<int, double>(arg1, p2: arg2);
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    InstanceCreationExpression creation = statement.expression;
    if (useCFE) {
      expect(creation.staticType, isDynamicType);
    }

    ConstructorName constructorName = creation.constructorName;
    expect(constructorName.name, isNull);

    TypeName typeName = constructorName.type;
    if (useCFE) {
      expect(typeName.type, isDynamicType);
    }

    SimpleIdentifier typeIdentifier = typeName.name;
    expect(typeIdentifier.staticElement, isNull);
    if (useCFE) {
      expect(typeIdentifier.staticType, isDynamicType);
    }

    assertTypeArguments(typeName.typeArguments, [intType, doubleType]);
    _assertInvocationArguments(creation.argumentList,
        [checkTopVarRef('arg1'), checkTopVarUndefinedNamedRef('arg2')]);
  }

  test_unresolved_instanceCreation_name_21() async {
    addTestFile(r'''
int arg1, arg2;
main() {
  new foo.Bar<int, double>(arg1, p2: arg2);
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    InstanceCreationExpression creation = statement.expression;
    if (useCFE) {
      expect(creation.staticType, isDynamicType);
    }

    ConstructorName constructorName = creation.constructorName;
    expect(constructorName.name, isNull);

    TypeName typeName = constructorName.type;
    if (useCFE) {
      expect(typeName.type, isDynamicType);
    }

    PrefixedIdentifier typePrefixed = typeName.name;
    expect(typePrefixed.staticElement, isNull);
    if (useCFE) {
      expect(typePrefixed.staticType, isDynamicType);
    }

    SimpleIdentifier typePrefix = typePrefixed.prefix;
    expect(typePrefix.staticElement, isNull);
    if (useCFE) {
      expect(typePrefix.staticType, isDynamicType);
    }

    SimpleIdentifier typeIdentifier = typePrefixed.identifier;
    expect(typeIdentifier.staticElement, isNull);
    if (useCFE) {
      expect(typePrefix.staticType, isDynamicType);
    }

    assertTypeArguments(typeName.typeArguments, [intType, doubleType]);
    _assertInvocationArguments(creation.argumentList,
        [checkTopVarRef('arg1'), checkTopVarUndefinedNamedRef('arg2')]);
  }

  test_unresolved_instanceCreation_name_22() async {
    addTestFile(r'''
import 'dart:math' as foo;
int arg1, arg2;
main() {
  new foo.Bar<int, double>(arg1, p2: arg2);
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var unitElement = result.unit.element;
    var foo = unitElement.library.imports[0].prefix;

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    InstanceCreationExpression creation = statement.expression;
    if (useCFE) {
      expect(creation.staticType, isDynamicType);
    }

    ConstructorName constructorName = creation.constructorName;
    expect(constructorName.name, isNull);

    TypeName typeName = constructorName.type;
    if (useCFE) {
      expect(typeName.type, isDynamicType);
    }

    PrefixedIdentifier typePrefixed = typeName.name;
    expect(typePrefixed.staticElement, isNull);
    if (useCFE) {
      expect(typePrefixed.staticType, isDynamicType);
    }

    SimpleIdentifier typePrefix = typePrefixed.prefix;
    expect(typePrefix.staticElement, same(foo));
    expect(typePrefix.staticType, isNull);

    SimpleIdentifier typeIdentifier = typePrefixed.identifier;
    expect(typeIdentifier.staticElement, isNull);
    if (useCFE) {
      expect(typePrefix.staticType, isDynamicType);
    }

    assertTypeArguments(typeName.typeArguments, [intType, doubleType]);
    _assertInvocationArguments(creation.argumentList,
        [checkTopVarRef('arg1'), checkTopVarUndefinedNamedRef('arg2')]);
  }

  test_unresolved_instanceCreation_name_31() async {
    addTestFile(r'''
int arg1, arg2;
main() {
  new foo.Bar<int, double>.baz(arg1, p2: arg2);
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    InstanceCreationExpression creation = statement.expression;
    if (useCFE) {
      expect(creation.staticType, isDynamicType);
    }

    ConstructorName constructorName = creation.constructorName;

    TypeName typeName = constructorName.type;
    if (useCFE) {
      expect(typeName.type, isDynamicType);
    }

    PrefixedIdentifier typePrefixed = typeName.name;
    expect(typePrefixed.staticElement, isNull);
    if (useCFE) {
      expect(typePrefixed.staticType, isDynamicType);
    }

    SimpleIdentifier typePrefix = typePrefixed.prefix;
    expect(typePrefix.staticElement, isNull);
    if (useCFE) {
      expect(typePrefix.staticType, isDynamicType);
    }

    SimpleIdentifier typeIdentifier = typePrefixed.identifier;
    expect(typeIdentifier.staticElement, isNull);
    if (useCFE) {
      expect(typePrefix.staticType, isDynamicType);
    }

    expect(constructorName.name.staticElement, isNull);
    if (useCFE) {
      expect(constructorName.name.staticType, isDynamicType);
    }

    assertTypeArguments(typeName.typeArguments, [intType, doubleType]);
    _assertInvocationArguments(creation.argumentList,
        [checkTopVarRef('arg1'), checkTopVarUndefinedNamedRef('arg2')]);
  }

  test_unresolved_instanceCreation_name_32() async {
    addTestFile(r'''
import 'dart:math' as foo;
int arg1, arg2;
main() {
  new foo.Bar<int, double>.baz(arg1, p2: arg2);
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var unitElement = result.unit.element;
    var mathImport = unitElement.library.imports[0];
    var foo = mathImport.prefix;

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    InstanceCreationExpression creation = statement.expression;
    if (useCFE) {
      expect(creation.staticType, isDynamicType);
    }

    ConstructorName constructorName = creation.constructorName;

    TypeName typeName = constructorName.type;
    if (useCFE) {
      expect(typeName.type, isDynamicType);
    }

    PrefixedIdentifier typePrefixed = typeName.name;
    expect(typePrefixed.staticElement, isNull);
    if (useCFE) {
      expect(typePrefixed.staticType, isDynamicType);
    }

    SimpleIdentifier typePrefix = typePrefixed.prefix;
    expect(typePrefix.staticElement, same(foo));
    expect(typePrefix.staticType, isNull);

    SimpleIdentifier typeIdentifier = typePrefixed.identifier;
    expect(typeIdentifier.staticElement, isNull);
    if (useCFE) {
      expect(typePrefix.staticType, isNull);
    }

    expect(constructorName.name.staticElement, isNull);
    expect(constructorName.name.staticType, isNull);

    assertTypeArguments(typeName.typeArguments, [intType, doubleType]);
    _assertInvocationArguments(creation.argumentList,
        [checkTopVarRef('arg1'), checkTopVarUndefinedNamedRef('arg2')]);
  }

  test_unresolved_instanceCreation_name_33() async {
    addTestFile(r'''
import 'dart:math' as foo;
int arg1, arg2;
main() {
  new foo.Random<int, double>.baz(arg1, p2: arg2);
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var unitElement = result.unit.element;
    var mathImport = unitElement.library.imports[0];
    var foo = mathImport.prefix;
    var randomElement = mathImport.importedLibrary.getType('Random');

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    InstanceCreationExpression creation = statement.expression;
    if (useCFE) {
      expect(creation.staticType, isDynamicType);
    }

    ConstructorName constructorName = creation.constructorName;

    TypeName typeName = constructorName.type;
    if (useCFE) {
      expect(typeName.type, isDynamicType);
    }

    PrefixedIdentifier typePrefixed = typeName.name;
    expect(typePrefixed.staticElement, same(randomElement));
    expect(typePrefixed.staticType, randomElement.type);

    SimpleIdentifier typePrefix = typePrefixed.prefix;
    expect(typePrefix.staticElement, same(foo));
    expect(typePrefix.staticType, isNull);

    SimpleIdentifier typeIdentifier = typePrefixed.identifier;
    expect(typeIdentifier.staticElement, same(randomElement));
    expect(typePrefix.staticType, isNull);

    expect(constructorName.name.staticElement, isNull);
    expect(constructorName.name.staticType, isNull);

    assertTypeArguments(typeName.typeArguments, [intType, doubleType]);
    _assertInvocationArguments(creation.argumentList,
        [checkTopVarRef('arg1'), checkTopVarUndefinedNamedRef('arg2')]);
  }

  test_unresolved_methodInvocation_noTarget() async {
    addTestFile(r'''
int arg1, arg2;
main() {
  bar<int, double>(arg1, p2: arg2);
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    MethodInvocation invocation = statement.expression;
    expect(invocation.target, isNull);
    expect(invocation.staticType, isDynamicType);
    expect(invocation.staticInvokeType, isDynamicType);

    SimpleIdentifier name = invocation.methodName;
    expect(name.staticElement, isNull);
    expect(name.staticType, isDynamicType);

    assertTypeArguments(invocation.typeArguments, [intType, doubleType]);
    _assertInvocationArguments(invocation.argumentList,
        [checkTopVarRef('arg1'), checkTopVarUndefinedNamedRef('arg2')]);
  }

  test_unresolved_methodInvocation_target_resolved() async {
    addTestFile(r'''
Object foo;
int arg1, arg2;
main() {
  foo.bar<int, double>(arg1, p2: arg2);
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    TopLevelVariableElement foo = _getTopLevelVariable(result, 'foo');

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    MethodInvocation invocation = statement.expression;
    expect(invocation.staticType, isDynamicType);
    if (useCFE) {
      // TODO(scheglov) https://github.com/dart-lang/sdk/issues/33682
      expect(invocation.staticInvokeType.toString(), '() → dynamic');
    } else {
      expect(invocation.staticInvokeType, isDynamicType);
    }

    SimpleIdentifier target = invocation.target;
    expect(target.staticElement, same(foo.getter));
    expect(target.staticType, typeProvider.objectType);

    SimpleIdentifier name = invocation.methodName;
    expect(name.staticElement, isNull);
    if (useCFE) {
      // TODO(scheglov) https://github.com/dart-lang/sdk/issues/33682
      expect(name.staticType.toString(), '() → dynamic');
    } else {
      expect(name.staticType, isDynamicType);
    }

    assertTypeArguments(invocation.typeArguments, [intType, doubleType]);
    _assertInvocationArguments(invocation.argumentList,
        [checkTopVarRef('arg1'), checkTopVarUndefinedNamedRef('arg2')]);
  }

  test_unresolved_methodInvocation_target_unresolved() async {
    addTestFile(r'''
int arg1, arg2;
main() {
  foo.bar<int, double>(arg1, p2: arg2);
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    MethodInvocation invocation = statement.expression;
    expect(invocation.staticType, isDynamicType);
    expect(invocation.staticInvokeType, isDynamicType);

    SimpleIdentifier target = invocation.target;
    expect(target.staticElement, isNull);
    expect(target.staticType, isDynamicType);

    SimpleIdentifier name = invocation.methodName;
    expect(name.staticElement, isNull);
    expect(name.staticType, isDynamicType);

    assertTypeArguments(invocation.typeArguments, [intType, doubleType]);
    _assertInvocationArguments(invocation.argumentList,
        [checkTopVarRef('arg1'), checkTopVarUndefinedNamedRef('arg2')]);
  }

  test_unresolved_postfix_operand() async {
    addTestFile(r'''
main() {
  a++;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var postfix = findNode.postfix('a++');
    assertElementNull(postfix);
    assertTypeDynamic(postfix);

    SimpleIdentifier aRef = postfix.operand;
    assertElementNull(aRef);
    assertTypeDynamic(aRef);
  }

  test_unresolved_postfix_operator() async {
    addTestFile(r'''
A a;
main() {
  a++;
}
class A {}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var postfix = findNode.postfix('a++');
    assertElementNull(postfix);
    assertType(postfix, 'A');

    SimpleIdentifier aRef = postfix.operand;
    assertElement(aRef, findElement.topSet('a'));
    assertType(aRef, 'A');
  }

  test_unresolved_prefix_operand() async {
    addTestFile(r'''
main() {
  ++a;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var prefix = findNode.prefix('++a');
    assertElementNull(prefix);
    assertTypeDynamic(prefix);

    SimpleIdentifier aRef = prefix.operand;
    assertElementNull(aRef);
    assertTypeDynamic(aRef);
  }

  test_unresolved_prefix_operator() async {
    addTestFile(r'''
A a;
main() {
  ++a;
}
class A {}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var prefix = findNode.prefix('++a');
    assertElementNull(prefix);
    assertTypeDynamic(prefix);

    SimpleIdentifier aRef = prefix.operand;
    assertElement(aRef, findElement.topSet('a'));
    assertType(aRef, 'A');
  }

  test_unresolved_prefixedIdentifier_identifier() async {
    addTestFile(r'''
Object foo;
main() {
  foo.bar;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    TopLevelVariableElement foo = _getTopLevelVariable(result, 'foo');

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    PrefixedIdentifier prefixed = statement.expression;
    expect(prefixed.staticElement, isNull);
    expect(prefixed.staticType, isDynamicType);

    SimpleIdentifier prefix = prefixed.prefix;
    expect(prefix.staticElement, same(foo.getter));
    expect(prefix.staticType, typeProvider.objectType);

    SimpleIdentifier identifier = prefixed.identifier;
    expect(identifier.staticElement, isNull);
    expect(identifier.staticType, isDynamicType);
  }

  test_unresolved_prefixedIdentifier_prefix() async {
    addTestFile(r'''
main() {
  foo.bar;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    PrefixedIdentifier prefixed = statement.expression;
    expect(prefixed.staticElement, isNull);
    expect(prefixed.staticType, isDynamicType);

    SimpleIdentifier prefix = prefixed.prefix;
    expect(prefix.staticElement, isNull);
    expect(prefix.staticType, isDynamicType);

    SimpleIdentifier identifier = prefixed.identifier;
    expect(identifier.staticElement, isNull);
    expect(identifier.staticType, isDynamicType);
  }

  test_unresolved_propertyAccess_1() async {
    addTestFile(r'''
main() {
  foo.bar.baz;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    PropertyAccess propertyAccess = statement.expression;
    expect(propertyAccess.staticType, isDynamicType);

    {
      PrefixedIdentifier prefixed = propertyAccess.target;
      expect(prefixed.staticElement, isNull);
      expect(prefixed.staticType, isDynamicType);

      SimpleIdentifier prefix = prefixed.prefix;
      expect(prefix.staticElement, isNull);
      expect(prefix.staticType, isDynamicType);

      SimpleIdentifier identifier = prefixed.identifier;
      expect(identifier.staticElement, isNull);
      expect(identifier.staticType, isDynamicType);
    }

    SimpleIdentifier property = propertyAccess.propertyName;
    expect(property.staticElement, isNull);
    expect(property.staticType, isDynamicType);
  }

  test_unresolved_propertyAccess_2() async {
    addTestFile(r'''
Object foo;
main() {
  foo.bar.baz;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    TopLevelVariableElement foo = _getTopLevelVariable(result, 'foo');

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    PropertyAccess propertyAccess = statement.expression;
    expect(propertyAccess.staticType, isDynamicType);

    {
      PrefixedIdentifier prefixed = propertyAccess.target;
      expect(prefixed.staticElement, isNull);
      expect(prefixed.staticType, isDynamicType);

      SimpleIdentifier prefix = prefixed.prefix;
      expect(prefix.staticElement, same(foo.getter));
      expect(prefix.staticType, typeProvider.objectType);

      SimpleIdentifier identifier = prefixed.identifier;
      expect(identifier.staticElement, isNull);
      expect(identifier.staticType, isDynamicType);
    }

    SimpleIdentifier property = propertyAccess.propertyName;
    expect(property.staticElement, isNull);
    expect(property.staticType, isDynamicType);
  }

  test_unresolved_propertyAccess_3() async {
    addTestFile(r'''
Object foo;
main() {
  foo.hashCode.baz;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    PropertyAccessorElement objectHashCode =
        typeProvider.objectType.getGetter('hashCode');
    TopLevelVariableElement foo = _getTopLevelVariable(result, 'foo');

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];

    PropertyAccess propertyAccess = statement.expression;
    expect(propertyAccess.staticType, isDynamicType);

    {
      PrefixedIdentifier prefixed = propertyAccess.target;
      expect(prefixed.staticElement, same(objectHashCode));
      expect(prefixed.staticType, typeProvider.intType);

      SimpleIdentifier prefix = prefixed.prefix;
      expect(prefix.staticElement, same(foo.getter));
      expect(prefix.staticType, typeProvider.objectType);

      SimpleIdentifier identifier = prefixed.identifier;
      expect(identifier.staticElement, same(objectHashCode));
      expect(identifier.staticType, typeProvider.intType);
    }

    SimpleIdentifier property = propertyAccess.propertyName;
    expect(property.staticElement, isNull);
    expect(property.staticType, isDynamicType);
  }

  test_unresolved_simpleIdentifier() async {
    addTestFile(r'''
main() {
  foo;
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    List<Statement> statements = _getMainStatements(result);
    ExpressionStatement statement = statements[0];
    SimpleIdentifier identifier = statement.expression;
    expect(identifier.staticElement, isNull);
    expect(identifier.staticType, isDynamicType);
  }

  test_unresolved_static_call() async {
    addTestFile('''
class C {
  static f() => C.g();
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var g = findNode.simple('g()');
    assertElementNull(g);
    assertTypeDynamic(g);
    var invocation = g.parent as MethodInvocation;
    assertTypeDynamic(invocation);
    expect(invocation.staticInvokeType, isDynamicType);
  }

  test_unresolved_static_call_arguments() async {
    addTestFile('''
int x;
class C {
  static f() => C.g(x);
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var x = findNode.simple('x)');
    assertElement(x, findElement.topGet('x'));
    assertType(x, 'int');
  }

  test_unresolved_static_call_same_name_as_type_param() async {
    addTestFile('''
class C<T> {
  static f() => C.T();
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var t = findNode.simple('T()');
    assertElementNull(t);
    assertTypeDynamic(t);
    var invocation = t.parent as MethodInvocation;
    assertTypeDynamic(invocation);
    expect(invocation.staticInvokeType, isDynamicType);
  }

  test_unresolved_static_call_type_arguments() async {
    addTestFile('''
class C {
  static f() => C.g<int>();
}
''');
    await resolveTestFile();
    expect(result.errors, isNotEmpty);

    var intRef = findNode.simple('int>');
    assertElement(intRef, intType.element);
    assertType(intRef, 'int');
  }

  /// Assert that the [argument] is associated with the [expectedParameter],
  /// if [useCFE] is `null`. If the [argument] is a [NamedExpression],
  /// the name must be resolved to the parameter in both cases.
  void _assertArgumentToParameter(
      Expression argument, ParameterElement expectedParameter,
      {DartType parameterMemberType}) {
    ParameterElement actualParameter = argument.staticParameterElement;
    if (useCFE) {
      expect(actualParameter, isNull);
      if (argument is NamedExpression) {
        SimpleIdentifier name = argument.name.label;
        expect(name.staticElement, same(expectedParameter));
      }
    } else {
      ParameterElement baseActualParameter;
      if (actualParameter is ParameterMember) {
        if (parameterMemberType != null) {
          expect(actualParameter.type, parameterMemberType);
        }
        baseActualParameter = actualParameter.baseElement;
        // Unwrap ParameterMember one more time.
        // By some reason we wrap in twice.
        if (baseActualParameter is ParameterMember) {
          ParameterMember member = baseActualParameter;
          baseActualParameter = member.baseElement;
        }
      } else {
        baseActualParameter = actualParameter;
      }
      expect(baseActualParameter, same(expectedParameter));
      if (argument is NamedExpression) {
        SimpleIdentifier name = argument.name.label;
        expect(name.staticElement, same(actualParameter));
      }
    }
  }

  void _assertDefaultParameter(
      DefaultFormalParameter node, ParameterElement element,
      {String name, int offset, ParameterKind kind, DartType type}) {
    expect(node, isNotNull);
    NormalFormalParameter normalNode = node.parameter;
    _assertSimpleParameter(normalNode, element,
        name: name, offset: offset, kind: kind, type: type);
  }

  /// Assert that the [type] is a function type `() -> dynamic`.
  void _assertDynamicFunctionType(DartType type) {
    if (useCFE) {
      expect(type.toString(), '() → dynamic');
    } else {
      expect(type, DynamicTypeImpl.instance);
    }
  }

  /// Test that [argumentList] has exactly two arguments - required `arg1`, and
  /// unresolved named `arg2`, both are the reference to top-level variables.
  void _assertInvocationArguments(ArgumentList argumentList,
      List<void Function(Expression)> argumentCheckers) {
    expect(argumentList.arguments, hasLength(argumentCheckers.length));
    for (int i = 0; i < argumentCheckers.length; i++) {
      argumentCheckers[i](argumentList.arguments[i]);
    }
  }

  void _assertParameterElement(ParameterElement element,
      {String name, int offset, ParameterKind kind, DartType type}) {
    expect(element, isNotNull);
    expect(name, isNotNull);
    expect(offset, isNotNull);
    expect(kind, isNotNull);
    expect(type, isNotNull);
    expect(element.name, name);
    expect(element.nameOffset, offset);
    // ignore: deprecated_member_use
    expect(element.parameterKind, kind);
    expect(element.type, type);
  }

  void _assertSimpleParameter(
      SimpleFormalParameter node, ParameterElement element,
      {String name, int offset, ParameterKind kind, DartType type}) {
    _assertParameterElement(element,
        name: name, offset: offset, kind: kind, type: type);

    expect(node, isNotNull);
    expect(node.element, same(element));
    expect(node.identifier.staticElement, same(element));

    TypeName typeName = node.type;
    if (typeName != null) {
      expect(typeName.type, same(type));
      expect(typeName.name.staticElement, same(type.element));
    }
  }

  void _assertTypeNameSimple(TypeName typeName, DartType type) {
    expect(typeName.type, type);

    SimpleIdentifier identifier = typeName.name;
    expect(identifier.staticElement, same(type.element));
    expect(identifier.staticType, type);
  }

  List<Statement> _getMainStatements(AnalysisResult result) {
    for (var declaration in result.unit.declarations) {
      if (declaration is FunctionDeclaration &&
          declaration.name.name == 'main') {
        BlockFunctionBody body = declaration.functionExpression.body;
        return body.block.statements;
      }
    }
    fail('Not found main() in ${result.unit}');
  }

  TopLevelVariableElement _getTopLevelVariable(
      AnalysisResult result, String name) {
    for (var variable in result.unit.element.topLevelVariables) {
      if (variable.name == name) {
        return variable;
      }
    }
    fail('Not found $name');
  }

  /**
   * Return the [provider] specific path for the given Posix [path].
   */
  String _p(String path) => provider.convertPath(path);
}

class FindElement {
  final AnalysisResult result;

  FindElement(this.result);

  CompilationUnitElement get unitElement => result.unit.element;

  ClassElement class_(String name) {
    for (var class_ in unitElement.types) {
      if (class_.name == name) {
        return class_;
      }
    }
    fail('Not found class: $name');
  }

  FieldElement field(String name) {
    for (var type in unitElement.types) {
      for (var field in type.fields) {
        if (field.name == name) {
          return field;
        }
      }
    }
    fail('Not found class field: $name');
  }

  FunctionElement function(String name) {
    for (var function in unitElement.functions) {
      if (function.name == name) {
        return function;
      }
    }
    fail('Not found top-level function: $name');
  }

  PropertyAccessorElement getter(String name) {
    for (var class_ in unitElement.types) {
      for (var accessor in class_.accessors) {
        if (accessor.isGetter && accessor.name == name) {
          return accessor;
        }
      }
    }
    fail('Not found class accessor: $name');
  }

  MethodElement method(String name) {
    for (var type in unitElement.types) {
      for (var method in type.methods) {
        if (method.name == name) {
          return method;
        }
      }
    }
    fail('Not found class method: $name');
  }

  PrefixElement prefix(String name) {
    for (var import_ in unitElement.library.imports) {
      var prefix = import_.prefix;
      if (prefix != null && prefix.name == name) {
        return prefix;
      }
    }
    fail('Prefix not found: $name');
  }

  PropertyAccessorElement topGet(String name) {
    return topVar(name).getter;
  }

  PropertyAccessorElement topSet(String name) {
    return topVar(name).setter;
  }

  TopLevelVariableElement topVar(String name) {
    for (var variable in unitElement.topLevelVariables) {
      if (variable.name == name) {
        return variable;
      }
    }
    fail('Not found top-level variable: $name');
  }

  TypeParameterElement typeParameter(String name) {
    for (var type in unitElement.types) {
      for (var parameter in type.typeParameters) {
        if (parameter.name == name) {
          return parameter;
        }
      }
    }
    fail('Not found type parameter: $name');
  }
}

class FindNode {
  final AnalysisResult result;

  FindNode(this.result);

  AssignmentExpression assignment(String search) {
    return _node(search).getAncestor((n) => n is AssignmentExpression);
  }

  CascadeExpression cascade(String search) {
    return _node(search).getAncestor((n) => n is CascadeExpression);
  }

  FunctionExpression functionExpression(String search) {
    return _node(search).getAncestor((n) => n is FunctionExpression);
  }

  InstanceCreationExpression instanceCreation(String search) {
    return _node(search).getAncestor((n) => n is InstanceCreationExpression);
  }

  MethodInvocation methodInvocation(String search) {
    return _node(search).getAncestor((n) => n is MethodInvocation);
  }

  PostfixExpression postfix(String search) {
    return _node(search).getAncestor((n) => n is PostfixExpression);
  }

  PrefixExpression prefix(String search) {
    return _node(search).getAncestor((n) => n is PrefixExpression);
  }

  SimpleIdentifier simple(String search) {
    return _node(search);
  }

  VariableDeclaration variableDeclaration(String search) {
    return _node(search).getAncestor((n) => n is VariableDeclaration);
  }

  AstNode _node(String search) {
    var content = result.content;
    var index = content.indexOf(search);
    if (content.indexOf(search, index + 1) != -1) {
      fail('The pattern |$search| is not unique in:\n$content');
    }
    expect(index, greaterThanOrEqualTo(0));
    return new NodeLocator2(index).searchWithin(result.unit);
  }
}
