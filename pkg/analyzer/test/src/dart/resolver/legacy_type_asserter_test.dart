// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/resolver/legacy_type_asserter.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:analyzer/src/generated/testing/ast_test_factory.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../resolution/driver_resolution.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(LegacyTypeAsserterTest);
  });
}

/// Tests for the [ExitDetector] that require that the control flow and spread
/// experiments be enabled.
@reflectiveTest
class LegacyTypeAsserterTest extends DriverResolutionTest {
  TypeProvider typeProvider;
  setUp() async {
    await super.setUp();
    typeProvider = await this.driver.currentSession.typeProvider;
  }

  test_nullableUnit_expressionStaticType_bottom() async {
    var identifier = AstTestFactory.identifier3('foo');
    var unit = _wrapExpression(identifier);
    identifier.staticType = BottomTypeImpl.instance;
    expect(() {
      LegacyTypeAsserter.assertLegacyTypes(unit);
    }, throwsStateError);
  }

  test_nullableUnit_expressionStaticType_bottomQuestion() async {
    var identifier = AstTestFactory.identifier3('foo');
    var unit = _wrapExpression(identifier);
    identifier.staticType = BottomTypeImpl.instanceNullable;
    LegacyTypeAsserter.assertLegacyTypes(unit);
  }

  test_nullableUnit_expressionStaticType_dynamic() async {
    var identifier = AstTestFactory.identifier3('foo');
    var unit = _wrapExpression(identifier);
    identifier.staticType = typeProvider.dynamicType;
    LegacyTypeAsserter.assertLegacyTypes(unit);
  }

  test_nullableUnit_expressionStaticType_nonNull() async {
    var identifier = AstTestFactory.identifier3('foo');
    var unit = _wrapExpression(identifier);
    identifier.staticType = (typeProvider.intType as TypeImpl)
        .withNullability(NullabilitySuffix.none);
    expect(() {
      LegacyTypeAsserter.assertLegacyTypes(unit);
    }, throwsStateError);
  }

  test_nullableUnit_expressionStaticType_nonNullTypeArgument() async {
    var identifier = AstTestFactory.identifier3('foo');
    var unit = _wrapExpression(identifier);
    identifier.staticType = typeProvider.listType.instantiate([
      (typeProvider.intType as TypeImpl)
          .withNullability(NullabilitySuffix.question)
    ]);

    expect(() {
      LegacyTypeAsserter.assertLegacyTypes(unit);
    }, throwsStateError);
  }

  test_nullableUnit_expressionStaticType_nonNullTypeParameter() async {
    var identifier = AstTestFactory.identifier3('foo');
    var unit = _wrapExpression(identifier);
    final listType = typeProvider.listType;
    listType.typeParameters[0] = TypeParameterElementImpl('E', 0)
      ..type = (listType.typeParameters[0].type as TypeImpl)
          .withNullability(NullabilitySuffix.none) as TypeParameterTypeImpl;
    identifier.staticType = listType;
    expect(
        (listType as dynamic)
            .typeParameters[0]
            .type
            .toString(withNullability: true),
        'E');
    expect(() {
      LegacyTypeAsserter.assertLegacyTypes(unit);
    }, throwsStateError);
  }

  test_nullableUnit_expressionStaticType_nonNullTypeParameterBound() async {
    var identifier = AstTestFactory.identifier3('foo');
    var unit = _wrapExpression(identifier);
    final listType = typeProvider.listType;
    (listType.typeParameters[0] as TypeParameterElementImpl).bound =
        (typeProvider.intType as TypeImpl)
            .withNullability(NullabilitySuffix.none);
    identifier.staticType = listType;
    expect(
        (listType as dynamic)
            .typeParameters[0]
            .type
            .bound
            .toString(withNullability: true),
        'int');
    expect(() {
      LegacyTypeAsserter.assertLegacyTypes(unit);
    }, throwsStateError);
  }

  test_nullableUnit_expressionStaticType_null() async {
    var identifier = AstTestFactory.identifier3('foo');
    var unit = _wrapExpression(identifier);
    identifier.staticType = typeProvider.nullType;
    LegacyTypeAsserter.assertLegacyTypes(unit);
  }

  test_nullableUnit_expressionStaticType_question() async {
    var identifier = AstTestFactory.identifier3('foo');
    var unit = _wrapExpression(identifier);
    identifier.staticType = (typeProvider.intType as TypeImpl)
        .withNullability(NullabilitySuffix.question);
    expect(() {
      LegacyTypeAsserter.assertLegacyTypes(unit);
    }, throwsStateError);
  }

  test_nullableUnit_expressionStaticType_star() async {
    var identifier = AstTestFactory.identifier3('foo');
    var unit = _wrapExpression(identifier);
    identifier.staticType = (typeProvider.intType as TypeImpl)
        .withNullability(NullabilitySuffix.star);
    LegacyTypeAsserter.assertLegacyTypes(unit);
  }

  test_nullableUnit_expressionStaticType_void() async {
    var identifier = AstTestFactory.identifier3('foo');
    var unit = _wrapExpression(identifier);
    identifier.staticType = VoidTypeImpl.instance;
    LegacyTypeAsserter.assertLegacyTypes(unit);
  }

  CompilationUnit _wrapExpression(Expression e, {bool nonNullable = false}) {
    return AstTestFactory.compilationUnit9(
        declarations: [
          AstTestFactory.functionDeclaration(
              null,
              null,
              null,
              AstTestFactory.functionExpression2(
                  null, AstTestFactory.expressionFunctionBody(e)))
        ],
        featureSet: FeatureSet.forTesting(
            additionalFeatures: nonNullable ? [Feature.non_nullable] : []));
  }
}
