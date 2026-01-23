// Cocoon wrapper for Rails importmaps
import $ from 'jquery';

(function($) {
  var create_new_id = function() {
    return (new Date).getTime() + n++;
  };
  
  var n = 0;
  
  var newcontent_braced = function(id) {
    return '[' + id + ']$1';
  };
  
  var newcontent_underscord = function(id) {
    return '_' + id + '_$1';
  };
  
  var getInsertionNodeElem = function(node, traversal, link) {
    if (!node) return link.parent();
    if (typeof node === 'function') {
      if (traversal) {
        console.warn('association-insertion-traversal is ignored, because association-insertion-node is given as a function.');
      }
      return node(link);
    }
    if (typeof node === 'string') {
      if (traversal) {
        return link[traversal](node);
      }
      if (node === 'this') {
        return link;
      }
      return $(node);
    }
    return undefined;
  };
  
  $(document).on('click', '.add_fields', function(e) {
    e.preventDefault();
    e.stopPropagation();
    
    var link = $(this);
    var association = link.data('association');
    var associations = link.data('associations');
    var template = link.data('association-insertion-template');
    var method = link.data('association-insertion-method') || link.data('association-insertion-position') || 'before';
    var node = link.data('association-insertion-node');
    var traversal = link.data('association-insertion-traversal');
    var count = parseInt(link.data('count'), 10);
    var regexp, regexp_underscord, new_id, new_content, insertionNode, event;
    
    new_id = create_new_id();
    regexp = new RegExp('\\[new_' + association + '\\](.*?\\s)', 'g');
    regexp_underscord = new RegExp('_new_' + association + '_(\\w*)', 'g');
    new_content = template.replace(regexp, newcontent_braced(new_id));
    
    if (new_content == template) {
      regexp = new RegExp('\\[new_' + associations + '\\](.*?\\s)', 'g');
      regexp_underscord = new RegExp('_new_' + associations + '_(\\w*)', 'g');
      new_content = template.replace(regexp, newcontent_braced(new_id));
    }
    
    new_content = new_content.replace(regexp_underscord, newcontent_underscord(new_id));
    
    var contents = [new_content];
    count = isNaN(count) ? 1 : Math.max(count, 1);
    count = count - 1;
    
    while (count) {
      new_id = create_new_id();
      new_content = template.replace(regexp, newcontent_braced(new_id));
      new_content = new_content.replace(regexp_underscord, newcontent_underscord(new_id));
      contents.push(new_content);
      count -= 1;
    }
    
    insertionNode = getInsertionNodeElem(node, traversal, link);
    
    if (!insertionNode || insertionNode.length === 0) {
      console.warn("Couldn't find the element to insert the template. Make sure your `data-association-insertion-*` on `link_to_add_association` is correct.");
    }
    
    $.each(contents, function(index, content) {
      var contentNode = $(content);
      event = $.Event('cocoon:before-insert');
      insertionNode.trigger(event, [contentNode, e]);
      
      if (!event.isDefaultPrevented()) {
        var addedContent = insertionNode[method](contentNode);
        insertionNode.trigger('cocoon:after-insert', [contentNode, e]);
      }
    });
  });
  
  $(document).on('click', '.remove_fields.dynamic, .remove_fields.existing', function(e) {
    var link = $(this);
    var wrapperClass = link.data('wrapper-class') || 'nested-fields';
    var wrapper = link.closest('.' + wrapperClass);
    var container = wrapper.parent();
    var event;
    
    e.preventDefault();
    e.stopPropagation();
    
    event = $.Event('cocoon:before-remove');
    container.trigger(event, [wrapper, e]);
    
    if (!event.isDefaultPrevented()) {
      var removeTimeout = container.data('remove-timeout') || 0;
      
      setTimeout(function() {
        if (link.hasClass('dynamic')) {
          wrapper.detach();
        } else {
          link.prev('input[type=hidden]').val('1');
          wrapper.hide();
        }
        container.trigger('cocoon:after-remove', [wrapper, e]);
      }, removeTimeout);
    }
  });
  
  $(document).on('ready page:load turbolinks:load', function() {
    $('.remove_fields.existing.destroyed').each(function() {
      var link = $(this);
      var wrapperClass = link.data('wrapper-class') || 'nested-fields';
      link.closest('.' + wrapperClass).hide();
    });
  });
  
})(jQuery);

// Create and export Cocoon object
const Cocoon = {
  Node: {
    PREDEFINED_CLASSES: ['fields', 'remove']
  },
  
  afterInsert: function(element) {
    $(element).trigger('cocoon:after-insert');
  },
  
  beforeInsert: function(element) {
    $(element).trigger('cocoon:before-insert');
  }
};

// Make it globally available
window.Cocoon = Cocoon;

// Export as ES module
export default Cocoon;
