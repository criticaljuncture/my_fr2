$(document).ready ->
  if $('.doc-public-inspection .doc-content').length > 0
    document_height = $('.doc-public-inspection .doc-content').outerHeight()
    sidebar_height = $('.doc-aside.doc-details').outerHeight()
    amount_document_should_be_lower_than_sidebar = 50
    side_bar_top_offset = 30

    if document_height < sidebar_height + amount_document_should_be_lower_than_sidebar
      $('.doc-content .fr-box')
        .css(
          'height',
          sidebar_height + amount_document_should_be_lower_than_sidebar + side_bar_top_offset
        )
