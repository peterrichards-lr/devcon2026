<#-- Attachment subfields are keyed by numeric object field ID, so find the image by pattern rather than by name -->
<#assign imageURL = "" />
<#list .data_model?keys as key>
	<#if key?starts_with("ObjectField_") && key?ends_with("#fileURL")>
		<#assign value = (.data_model[key].getData())!"" />
		<#if value?has_content>
			<#assign imageURL = value />
		</#if>
	</#if>
</#list>
<#if imageURL?has_content>
	<img class="w-100 h-auto" src="${imageURL}">
</#if>
