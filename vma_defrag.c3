module vma;

import vk;

fn DefragmentationContext? Allocator.try_begin_defragmentation(self, DefragmentationInfo* info) {
    DefragmentationContext ctx;
    check(self.begin_defragmentation(info, &ctx))!;
    return ctx;
}

<* Begin a defragmentation pass. Returns true if there are moves to process
   (VK_INCOMPLETE), false if defragmentation is finished (VK_SUCCESS). *>
fn bool? Allocator.try_begin_defragmentation_pass(self, DefragmentationContext ctx, DefragmentationPassMoveInfo* pass_info) {
    return check_pass(self.begin_defragmentation_pass(ctx, pass_info));
}

<* End a defragmentation pass. Returns true if another pass is needed
   (VK_INCOMPLETE), false if defragmentation is finished (VK_SUCCESS). *>
fn bool? Allocator.try_end_defragmentation_pass(self, DefragmentationContext ctx, DefragmentationPassMoveInfo* pass_info) {
    return check_pass(self.end_defragmentation_pass(ctx, pass_info));
}

<* Map a defragmentation pass result: SUCCESS -> false (done), INCOMPLETE -> true
   (more to do), any other result -> the corresponding vma fault. *>
fn bool? check_pass(vk::Result r) @private {
    switch (r) {
        case vk::Result.SUCCESS:    return false;
        case vk::Result.INCOMPLETE: return true;
        default:                    check(r)!;
    }
    return false;
}
