import pprint
pp = pprint.PrettyPrinter()
class DictDiffer(object):
    """
    Calculate the difference between two dictionaries as:
    (1) items added
    (2) items removed
    (3) keys same in both but changed values
    (4) keys same in both and unchanged values
    """
    def __init__(self, current_dict, past_dict):
      self.current_dict, self.past_dict = current_dict, past_dict
      self.set_current, self.set_past = set(current_dict.keys()), set(past_dict.keys())
      self.intersect = self.set_current.intersection(self.set_past)
    def added(self):
      return set(o for o in self.set_current - self.intersect)
    def removed(self):
      return set(o for o in self.set_past - self.intersect)
    def changed(self):
      return set(o for o in self.intersect if self.past_dict[o] != self.current_dict[o])
    def unchanged(self):
      return set(o for o in self.intersect if self.past_dict[o] == self.current_dict[o])
    def areEqual(self):
      ch = self.changed()
      ch = ch.union(self.removed(),self.added())
      if len(ch) == 0: return True
      print "Differences: %s" % (ch)
      print "Changed: %s" % (self.changed())
      print "Added: %s" % (self.added())
      print "Removed: %s" % (self.removed())
      for item in ch:
        if self.current_dict.has_key(item) and self.past_dict.has_key(item):
          print "%s got %s vs %s" % (item,self.current_dict[item],self.past_dict[item])
        elif self.current_dict.has_key(item) and not self.past_dict.has_key(item):
          print "%s got %s vs %s" % (item,self.current_dict[item],None)
        elif not self.current_dict.has_key(item) and self.past_dict.has_key(item):
          print "%s got %s vs %s" % (item,None,self.past_dict[item])
      return False

