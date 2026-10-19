package com.liferay.masterclass.cms.workarounds.internal.model.listener;

import com.liferay.fragment.model.FragmentEntryLink;
import com.liferay.object.model.ObjectDefinition;
import com.liferay.object.model.ObjectField;
import com.liferay.object.service.ObjectDefinitionLocalService;
import com.liferay.object.service.ObjectFieldLocalService;
import com.liferay.portal.kernel.json.JSONException;
import com.liferay.portal.kernel.json.JSONFactory;
import com.liferay.portal.kernel.json.JSONObject;
import com.liferay.portal.kernel.log.Log;
import com.liferay.portal.kernel.log.LogFactoryUtil;
import com.liferay.portal.kernel.model.BaseModelListener;
import com.liferay.portal.kernel.model.ModelListener;
import com.liferay.portal.kernel.util.Validator;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.osgi.service.component.annotations.Component;
import org.osgi.service.component.annotations.Reference;

/**
 * Resolves <code>[$OBJECT_FIELD_KEY:Object:field#subfield$]</code> tokens in
 * fragment mappings to the live object field ID.
 *
 * <p>An attachment field is only mappable through subfields keyed by its
 * numeric ID, such as <code>ObjectField_37434#fileURL</code>, which a site
 * initializer tree cannot name. Unknown tokens pass through the initializer
 * unchanged, so the tree carries one and this listener resolves it as the
 * fragment entry link is saved:</p>
 *
 * <ul>
 * <li>
 * In a collection item mapping the importer stores the field key verbatim, so
 * the token in <code>collectionFieldId</code> is replaced in place.
 * </li>
 * <li>
 * A display page mapping is validated by the importer and dropped when it does
 * not resolve, so there the tree puts the token in the editable's literal value
 * instead, and it becomes <code>mappedField</code> here. For a link that value
 * is the <code>href</code>, which the importer keeps in the editable's
 * <code>config</code>.
 * </li>
 * </ul>
 *
 * <p>Remove this bundle once the product can map an attachment subfield by
 * name, and switch the tree's tokens to that form at the same time. Links it
 * already rewrote hold real IDs and keep working.</p>
 */
@Component(service = ModelListener.class)
public class FragmentEntryLinkModelListener
	extends BaseModelListener<FragmentEntryLink> {

	@Override
	public void onBeforeCreate(FragmentEntryLink fragmentEntryLink) {
		_resolveTokens(fragmentEntryLink);
	}

	@Override
	public void onBeforeUpdate(
		FragmentEntryLink originalFragmentEntryLink,
		FragmentEntryLink fragmentEntryLink) {

		_resolveTokens(fragmentEntryLink);
	}

	private String _getFieldKey(long companyId, Matcher matcher) {
		String objectDefinitionName = matcher.group(1);

		ObjectDefinition objectDefinition =
			_objectDefinitionLocalService.fetchObjectDefinition(
				companyId, "C_" + objectDefinitionName);

		if (objectDefinition == null) {
			objectDefinition =
				_objectDefinitionLocalService.fetchObjectDefinition(
					companyId, objectDefinitionName);
		}

		if (objectDefinition == null) {
			_log.error("No object definition named " + objectDefinitionName);

			return null;
		}

		ObjectField objectField = _objectFieldLocalService.fetchObjectField(
			objectDefinition.getObjectDefinitionId(), matcher.group(2));

		if (objectField == null) {
			_log.error(
				"No field " + matcher.group(2) + " on " + objectDefinitionName);

			return null;
		}

		return "ObjectField_" + objectField.getObjectFieldId() +
			matcher.group(3);
	}

	private boolean _isLanguageId(String key) {
		Matcher matcher = _languageIdPattern.matcher(key);

		return matcher.matches();
	}

	private boolean _resolveEditable(
		long companyId, JSONObject editableJSONObject) {

		boolean resolved = _resolveMapping(companyId, editableJSONObject);

		JSONObject configJSONObject = editableJSONObject.getJSONObject(
			"config");

		if ((configJSONObject != null) &&
			_resolveLink(companyId, configJSONObject)) {

			resolved = true;
		}

		return resolved;
	}

	private boolean _resolveLink(long companyId, JSONObject configJSONObject) {
		String collectionFieldId = configJSONObject.getString(
			"collectionFieldId");

		Matcher matcher = _pattern.matcher(collectionFieldId);

		if (matcher.matches()) {
			String fieldKey = _getFieldKey(companyId, matcher);

			if (fieldKey == null) {
				return false;
			}

			configJSONObject.put("collectionFieldId", fieldKey);

			return true;
		}

		// A display page link mapping is dropped on import, so the token
		// arrives as a literal href, plain or per locale

		Object href = configJSONObject.get("href");

		String fieldKey = null;

		if (href instanceof String) {
			matcher = _pattern.matcher((String)href);

			if (matcher.matches()) {
				fieldKey = _getFieldKey(companyId, matcher);
			}
		}
		else if (href instanceof JSONObject) {
			JSONObject hrefJSONObject = (JSONObject)href;

			for (String key : hrefJSONObject.keySet()) {
				matcher = _pattern.matcher(hrefJSONObject.getString(key));

				if (matcher.matches()) {
					fieldKey = _getFieldKey(companyId, matcher);

					break;
				}
			}
		}

		if (fieldKey == null) {
			return false;
		}

		configJSONObject.remove("href");
		configJSONObject.put("mappedField", fieldKey);

		return true;
	}

	private boolean _resolveMapping(
		long companyId, JSONObject editableJSONObject) {

		String collectionFieldId = editableJSONObject.getString(
			"collectionFieldId");

		Matcher matcher = _pattern.matcher(collectionFieldId);

		if (matcher.matches()) {
			String fieldKey = _getFieldKey(companyId, matcher);

			if (fieldKey != null) {
				editableJSONObject.put("collectionFieldId", fieldKey);

				return true;
			}

			return false;
		}

		List<String> tokenKeys = new ArrayList<>();
		String fieldKey = null;

		for (String key : editableJSONObject.keySet()) {
			if (!_isLanguageId(key)) {
				continue;
			}

			matcher = _pattern.matcher(editableJSONObject.getString(key));

			if (!matcher.matches()) {
				continue;
			}

			tokenKeys.add(key);

			if (fieldKey == null) {
				fieldKey = _getFieldKey(companyId, matcher);
			}
		}

		if (fieldKey == null) {
			return false;
		}

		for (String key : tokenKeys) {
			editableJSONObject.remove(key);
		}

		editableJSONObject.put("mappedField", fieldKey);

		return true;
	}

	private void _resolveTokens(FragmentEntryLink fragmentEntryLink) {
		String editableValues = fragmentEntryLink.getEditableValues();

		if (Validator.isNull(editableValues) ||
			!editableValues.contains(_TOKEN_PREFIX)) {

			return;
		}

		try {
			JSONObject editableValuesJSONObject =
				_jsonFactory.createJSONObject(editableValues);

			JSONObject editablesJSONObject =
				editableValuesJSONObject.getJSONObject(
					_EDITABLE_FRAGMENT_ENTRY_PROCESSOR);

			if (editablesJSONObject == null) {
				return;
			}

			boolean resolved = false;

			for (String editableId : editablesJSONObject.keySet()) {
				JSONObject editableJSONObject =
					editablesJSONObject.getJSONObject(editableId);

				if ((editableJSONObject != null) &&
					_resolveEditable(
						fragmentEntryLink.getCompanyId(), editableJSONObject)) {

					resolved = true;
				}
			}

			if (resolved) {
				fragmentEntryLink.setEditableValues(
					editableValuesJSONObject.toString());
			}
		}
		catch (JSONException jsonException) {
			_log.error(
				"Unable to resolve tokens in fragment entry link " +
					fragmentEntryLink.getFragmentEntryLinkId(),
				jsonException);
		}
	}

	private static final String _EDITABLE_FRAGMENT_ENTRY_PROCESSOR =
		"com.liferay.fragment.entry.processor.editable." +
			"EditableFragmentEntryProcessor";

	private static final String _TOKEN_PREFIX = "[$OBJECT_FIELD_KEY:";

	private static final Log _log = LogFactoryUtil.getLog(
		FragmentEntryLinkModelListener.class);

	private static final Pattern _languageIdPattern = Pattern.compile(
		"[a-z]{2,3}(_[A-Z]{2})?");

	private static final Pattern _pattern = Pattern.compile(
		"\\s*\\[\\$OBJECT_FIELD_KEY:([A-Za-z0-9_]+):([A-Za-z0-9_]+)(#[A-Za-z]+)?" +
			"\\$\\]\\s*");

	@Reference
	private JSONFactory _jsonFactory;

	@Reference
	private ObjectDefinitionLocalService _objectDefinitionLocalService;

	@Reference
	private ObjectFieldLocalService _objectFieldLocalService;

}
