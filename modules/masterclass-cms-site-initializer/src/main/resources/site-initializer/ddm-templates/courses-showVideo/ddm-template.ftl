<#-- Find the attachment whose MIME type starts with video and print its download URL -->
<#assign downloadURL = "" />
<#list .data_model?keys as key>
	<#if key?starts_with("ObjectField_") && key?ends_with("#mimeType")>
		<#assign mimeType = (.data_model[key].getData())!"" />
		<#if mimeType?starts_with("video")>
			<#assign downloadKey = key?keep_before("#") + "#downloadURL" />
			<#assign downloadURL = (.data_model[downloadKey].getData())!"" />
		</#if>
	</#if>
</#list>
${downloadURL}
