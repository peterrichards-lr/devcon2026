package com.liferay.masterclass.cms.workarounds.internal.model.listener;

import com.liferay.asset.list.model.AssetListEntrySegmentsEntryRel;
import com.liferay.depot.constants.DepotConstants;
import com.liferay.depot.model.DepotEntry;
import com.liferay.depot.service.DepotEntryLocalService;
import com.liferay.petra.string.StringPool;
import com.liferay.portal.kernel.dao.orm.QueryUtil;
import com.liferay.portal.kernel.exception.PortalException;
import com.liferay.portal.kernel.log.Log;
import com.liferay.portal.kernel.log.LogFactoryUtil;
import com.liferay.portal.kernel.model.BaseModelListener;
import com.liferay.portal.kernel.model.Group;
import com.liferay.portal.kernel.model.ModelListener;
import com.liferay.portal.kernel.service.GroupLocalService;
import com.liferay.portal.kernel.util.GetterUtil;
import com.liferay.portal.kernel.util.SetUtil;
import com.liferay.portal.kernel.util.StringUtil;
import com.liferay.portal.kernel.util.UnicodeProperties;
import com.liferay.portal.kernel.util.UnicodePropertiesBuilder;

import java.util.LinkedHashSet;
import java.util.Set;

import org.osgi.service.component.annotations.Component;
import org.osgi.service.component.annotations.Reference;

/**
 * Widens a new collection's scope to the Spaces connected to its site.
 *
 * <p>The site initializer always writes <code>groupIds</code> as the site
 * alone (<code>BundleSiteInitializer._addOrUpdateAssetListEntry</code>), and
 * no token names a Space's group ID, so a collection over entries that live in
 * a Space renders "No Results Found" until someone adds the Space by hand.
 * </p>
 *
 * <p>Only acts on creation, so a scope an editor later narrows stays
 * narrowed. Remove this bundle once the initializer can scope a collection to
 * a Space itself.</p>
 */
@Component(service = ModelListener.class)
public class AssetListEntrySegmentsEntryRelModelListener
	extends BaseModelListener<AssetListEntrySegmentsEntryRel> {

	@Override
	public void onBeforeCreate(
		AssetListEntrySegmentsEntryRel assetListEntrySegmentsEntryRel) {

		try {
			_addConnectedSpaces(assetListEntrySegmentsEntryRel);
		}
		catch (PortalException portalException) {
			_log.error(
				"Unable to add connected Spaces to asset list entry " +
					assetListEntrySegmentsEntryRel.getAssetListEntryId(),
				portalException);
		}
	}

	private void _addConnectedSpaces(
			AssetListEntrySegmentsEntryRel assetListEntrySegmentsEntryRel)
		throws PortalException {

		long groupId = assetListEntrySegmentsEntryRel.getGroupId();

		Group group = _groupLocalService.fetchGroup(groupId);

		if ((group == null) ||
			!_SITE_FRIENDLY_URLS.contains(group.getFriendlyURL())) {

			return;
		}

		UnicodeProperties unicodeProperties = UnicodePropertiesBuilder.load(
			assetListEntrySegmentsEntryRel.getTypeSettings()
		).build();

		long[] groupIds = GetterUtil.getLongValues(
			StringUtil.split(
				unicodeProperties.getProperty("groupIds", StringPool.BLANK)));

		// Anything other than the site alone was chosen on purpose

		if ((groupIds.length != 1) || (groupIds[0] != groupId)) {
			return;
		}

		Set<Long> scopeGroupIds = new LinkedHashSet<>();

		scopeGroupIds.add(groupId);

		for (DepotEntry depotEntry :
				_depotEntryLocalService.getGroupConnectedDepotEntries(
					groupId, DepotConstants.TYPE_ANY, QueryUtil.ALL_POS,
					QueryUtil.ALL_POS)) {

			scopeGroupIds.add(depotEntry.getGroupId());
		}

		if (scopeGroupIds.size() == 1) {
			return;
		}

		unicodeProperties.setProperty(
			"groupIds", StringUtil.merge(scopeGroupIds, StringPool.COMMA));

		assetListEntrySegmentsEntryRel.setTypeSettings(
			unicodeProperties.toString());

		if (_log.isInfoEnabled()) {
			_log.info(
				"Scoped asset list entry " +
					assetListEntrySegmentsEntryRel.getAssetListEntryId() +
						" to groups " + scopeGroupIds);
		}
	}

	private static final Set<String> _SITE_FRIENDLY_URLS = SetUtil.fromArray(
		"/masterclass-cms");

	private static final Log _log = LogFactoryUtil.getLog(
		AssetListEntrySegmentsEntryRelModelListener.class);

	@Reference
	private DepotEntryLocalService _depotEntryLocalService;

	@Reference
	private GroupLocalService _groupLocalService;

}
