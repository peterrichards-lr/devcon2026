package com.liferay.masterclass.cms.workarounds.internal.model.listener;

import com.liferay.object.constants.ObjectValidationRuleConstants;
import com.liferay.object.constants.ObjectValidationRuleSettingConstants;
import com.liferay.object.exception.ObjectValidationRuleSettingValueException;
import com.liferay.object.model.ObjectDefinition;
import com.liferay.object.model.ObjectField;
import com.liferay.object.model.ObjectValidationRule;
import com.liferay.object.model.ObjectValidationRuleSetting;
import com.liferay.object.service.ObjectDefinitionLocalService;
import com.liferay.object.service.ObjectFieldLocalService;
import com.liferay.object.service.ObjectValidationRuleLocalService;
import com.liferay.object.service.ObjectValidationRuleSettingLocalService;
import com.liferay.portal.kernel.log.Log;
import com.liferay.portal.kernel.log.LogFactoryUtil;
import com.liferay.portal.kernel.model.BaseModelListener;
import com.liferay.portal.kernel.model.Company;
import com.liferay.portal.kernel.model.ModelListener;
import com.liferay.portal.kernel.service.CompanyLocalService;
import com.liferay.portal.kernel.transaction.TransactionCommitCallbackUtil;
import com.liferay.portal.kernel.util.LocaleUtil;
import com.liferay.portal.kernel.workflow.WorkflowConstants;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import org.osgi.service.component.annotations.Activate;
import org.osgi.service.component.annotations.Component;
import org.osgi.service.component.annotations.Reference;

/**
 * Adds a composite key validation rule to an object once its fields exist: on
 * MyCourseEnrollment, one registration per student per session.
 *
 * <p>A site initializer can declare validation rules inline in an object
 * definition, but not one over relationship fields: those fields are created
 * by the <code>object-relationships/</code> handler, which runs after the
 * definitions (Discuss #1074, UPSTREAM-FEEDBACK.md item 8). So the rule is
 * added once the definition's publication has committed (the initializer
 * publishes after creating the relationships). It is also tried for existing
 * definitions when this bundle starts, but the platform only allows a
 * composite key before an object has entries with values in its fields, so on
 * a site that already has enrolments it logs a warning and adds nothing.</p>
 *
 * <p>To reuse it for another object, add an entry to <code>_RULES</code>.
 * Each rule is found by its external reference code and never added twice.
 * Remove this listener once site initializers can declare validation rules
 * on relationship fields.</p>
 */
@Component(immediate = true, service = ModelListener.class)
public class ObjectDefinitionModelListener
	extends BaseModelListener<ObjectDefinition> {

	@Override
	public void onAfterUpdate(
		ObjectDefinition originalObjectDefinition,
		ObjectDefinition objectDefinition) {

		if (objectDefinition.getStatus() !=
				WorkflowConstants.STATUS_APPROVED) {

			return;
		}

		// Publishing marks the definition approved before it creates the
		// object's table, and adding a composite key rule queries that table.
		// Inside this transaction the query fails, and on PostgreSQL a failed
		// statement aborts the whole transaction, rolling back the site the
		// initializer is creating, however the exception is caught. So add the
		// rules after the transaction commits, in a transaction of their own.

		long objectDefinitionId = objectDefinition.getObjectDefinitionId();

		TransactionCommitCallbackUtil.registerCallback(
			() -> {
				ObjectDefinition committedObjectDefinition =
					_objectDefinitionLocalService.fetchObjectDefinition(
						objectDefinitionId);

				if (committedObjectDefinition != null) {
					_addRules(committedObjectDefinition);
				}

				return null;
			});
	}

	@Activate
	protected void activate() {
		for (Company company : _companyLocalService.getCompanies()) {
			for (CompositeKeyRule compositeKeyRule : _RULES) {
				ObjectDefinition objectDefinition =
					_objectDefinitionLocalService.
						fetchObjectDefinitionByExternalReferenceCode(
							compositeKeyRule._objectDefinitionExternalReferenceCode,
							company.getCompanyId());

				if ((objectDefinition != null) &&
					(objectDefinition.getStatus() ==
						WorkflowConstants.STATUS_APPROVED)) {

					_addRules(objectDefinition);
				}
			}
		}
	}

	private void _addRule(
		ObjectDefinition objectDefinition, CompositeKeyRule compositeKeyRule) {

		ObjectValidationRule objectValidationRule =
			_objectValidationRuleLocalService.fetchObjectValidationRule(
				compositeKeyRule._externalReferenceCode,
				objectDefinition.getObjectDefinitionId());

		if (objectValidationRule != null) {
			return;
		}

		List<ObjectValidationRuleSetting> objectValidationRuleSettings =
			new ArrayList<>();

		for (String objectFieldName : compositeKeyRule._objectFieldNames) {
			ObjectField objectField = _objectFieldLocalService.fetchObjectField(
				objectDefinition.getObjectDefinitionId(), objectFieldName);

			// The relationships have not all been created yet

			if (objectField == null) {
				if (_log.isDebugEnabled()) {
					_log.debug(
						"Not adding " + compositeKeyRule._externalReferenceCode +
							" yet: no field " + objectFieldName);
				}

				return;
			}

			ObjectValidationRuleSetting objectValidationRuleSetting =
				_objectValidationRuleSettingLocalService.
					createObjectValidationRuleSetting(0L);

			objectValidationRuleSetting.setName(
				ObjectValidationRuleSettingConstants.
					NAME_COMPOSITE_KEY_OBJECT_FIELD_ID);
			objectValidationRuleSetting.setValue(
				String.valueOf(objectField.getObjectFieldId()));

			objectValidationRuleSettings.add(objectValidationRuleSetting);
		}

		try {
			_objectValidationRuleLocalService.addObjectValidationRule(
				compositeKeyRule._externalReferenceCode,
				objectDefinition.getUserId(),
				objectDefinition.getObjectDefinitionId(), true,
				ObjectValidationRuleConstants.ENGINE_TYPE_COMPOSITE_KEY,
				Collections.singletonMap(
					LocaleUtil.US, compositeKeyRule._errorLabel),
				Collections.singletonMap(LocaleUtil.US, compositeKeyRule._name),
				ObjectValidationRuleConstants.OUTPUT_TYPE_FULL_VALIDATION, null,
				false, objectValidationRuleSettings);

			if (_log.isInfoEnabled()) {
				_log.info(
					"Added composite key rule " +
						compositeKeyRule._externalReferenceCode + " to " +
							objectDefinition.getShortName() + " over " +
								String.join(
									", ", compositeKeyRule._objectFieldNames));
			}
		}
		catch (ObjectValidationRuleSettingValueException.InvalidValue
					invalidValue) {

			// The platform won't add a composite key over a field that existing
			// entries already have values in, and reports it as an invalid
			// value. Expected when this bundle starts on a site that has data.

			_log.warn(
				"Not adding composite key rule " +
					compositeKeyRule._externalReferenceCode + " to " +
						objectDefinition.getShortName() +
							": it has entries already, and a composite key " +
								"can only be added before an object has entries " +
									"with values in its fields. Recreate the site " +
										"with this bundle deployed to get the rule (" +
											invalidValue.getMessage() + ")");
		}
		catch (Exception exception) {
			_log.error(
				"Unable to add composite key rule " +
					compositeKeyRule._externalReferenceCode + " to " +
						objectDefinition.getShortName(),
				exception);
		}
	}

	private void _addRules(ObjectDefinition objectDefinition) {
		for (CompositeKeyRule compositeKeyRule : _RULES) {
			if (compositeKeyRule._objectDefinitionExternalReferenceCode.equals(
					objectDefinition.getExternalReferenceCode())) {

				_addRule(objectDefinition, compositeKeyRule);
			}
		}
	}

	private static final List<CompositeKeyRule> _RULES = List.of(
		new CompositeKeyRule(
			"MY-COURSE-ENROLLMENT", "MY-COURSE-ENROLLMENT-ONE-PER-SESSION",
			"One registration per student per session",
			"You are already registered for this session.",
			"r_courseToUser_userId",
			"r_enrollmentToCourseSession_c_myCourseSessionId"));

	private static final Log _log = LogFactoryUtil.getLog(
		ObjectDefinitionModelListener.class);

	@Reference
	private CompanyLocalService _companyLocalService;

	@Reference
	private ObjectDefinitionLocalService _objectDefinitionLocalService;

	@Reference
	private ObjectFieldLocalService _objectFieldLocalService;

	@Reference
	private ObjectValidationRuleLocalService _objectValidationRuleLocalService;

	@Reference
	private ObjectValidationRuleSettingLocalService
		_objectValidationRuleSettingLocalService;

	private static class CompositeKeyRule {

		private CompositeKeyRule(
			String objectDefinitionExternalReferenceCode,
			String externalReferenceCode, String name, String errorLabel,
			String... objectFieldNames) {

			_objectDefinitionExternalReferenceCode =
				objectDefinitionExternalReferenceCode;
			_externalReferenceCode = externalReferenceCode;
			_name = name;
			_errorLabel = errorLabel;
			_objectFieldNames = objectFieldNames;
		}

		private final String _errorLabel;
		private final String _externalReferenceCode;
		private final String _name;
		private final String _objectDefinitionExternalReferenceCode;
		private final String[] _objectFieldNames;

	}

}
