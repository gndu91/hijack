/* 
 * QNX4 file system, Linux implementation.
 * 
 * Version : 0.2.1
 * 
 * Using parts of the xiafs filesystem.
 * 
 * History :
 * 
 * 01-06-1998 by Richard Frowijn : first release.
 * 20-06-1998 by Frank Denis : Linux 2.1.99+ support, boot signature, misc.
 * 30-06-1998 by Frank Denis : first step to write inodes.
 */

#include <linux/config.h>
#include <linux/module.h>
#include <linux/types.h>
#include <linux/errno.h>
#include <linux/malloc.h>
#include <linux/qnx4_fs.h>
#include <linux/fs.h>
#include <linux/locks.h>
#include <linux/init.h>

#include <asm/uaccess.h>

#define QNX4_VERSION  4
#define QNX4_BMNAME   ".bitmap"

static struct super_operations qnx4_sops;

#ifdef CONFIG_QNX4FS_RW

int qnx4_sync_inode(struct inode *inode)
{
	int err = 0;
# if 0
	struct buffer_head *bh;

   	bh = qnx4_update_inode(inode);
	if (bh && buffer_dirty(bh))
	{
		ll_rw_block(WRITE, 1, &bh);
		wait_on_buffer(bh);
		if (buffer_req(bh) && !buffer_uptodate(bh))
		{
			printk ("IO error syncing qnx4 inode [%s:%08lx]\n",
				kdevname(inode->i_dev), inode->i_ino);
			err = -1;
		}
	        brelse (bh);	   
	} else if (!bh) {
		err = -1;
	}
# endif

	return err;
}

static void qnx4_delete_inode(struct inode *inode)
{
	QNX4DEBUG(("qnx4: deleting inode [%lu]\n", (unsigned long) inode->i_ino));
	inode->i_size = 0;
	qnx4_truncate(inode);
	qnx4_free_inode(inode);
}

static void qnx4_write_super(struct super_block *sb)
{
	QNX4DEBUG(("qnx4: write_super\n"));
	sb->s_dirt = 0;
}

static void qnx4_put_inode(struct inode *inode)
{
	if (inode->i_nlink != 0) {
		return;
	}
	inode->i_size = 0;
}

static void qnx4_write_inode(struct inode *inode)
{
	struct qnx4_inode_entry *raw_inode;
	int block, ino;
	struct buffer_head *bh;
	ino = inode->i_ino;

	QNX4DEBUG(("qnx4: write inode 1.\n"));
	if (inode->i_nlink == 0) {
		return;
	}
	if (!ino) {
		printk("qnx4: bad inode number on dev %s: %d is out of range\n",
		       kdevname(inode->i_dev), ino);
		return;
	}
	QNX4DEBUG(("qnx4: write inode 2.\n"));
	block = ino / QNX4_INODES_PER_BLOCK;
	if (!(bh = bread(inode->i_dev, block, QNX4_BLOCK_SIZE))) {
		printk("qnx4: major problem: unable to read inode from dev "
		       "%s\n", kdevname(inode->i_dev));
		return;
	}
	raw_inode = ((struct qnx4_inode_entry *) bh->b_data) +
	    (ino % QNX4_INODES_PER_BLOCK);
	raw_inode->di_mode  = cpu_to_le16(inode->i_mode);
	raw_inode->di_uid   = cpu_to_le16(inode->i_uid);
	raw_inode->di_gid   = cpu_to_le16(inode->i_gid);
	raw_inode->di_nlink = cpu_to_le16(inode->i_nlink);
	raw_inode->di_size  = cpu_to_le32(inode->i_size);
	raw_inode->di_mtime = cpu_to_le32(inode->i_mtime);
	raw_inode->di_atime = cpu_to_le32(inode->i_atime);
	raw_inode->di_ctime = cpu_to_le32(inode->i_ctime);
	raw_inode->di_first_xtnt.xtnt_size = cpu_to_le32(inode->i_blocks);
	mark_buffer_dirty(bh, 1);
	brelse(bh);
}

#endif

static struct super_block *qnx4_read_super(struct super_block *, void *, int);
static void qnx4_put_super(struct super_block *sb);
static void qnx4_read_inode(struct inode *);
static int qnx4_remount(struct super_block *sb, int *flags, char *data);
static int qnx4_statfs(struct super_block *, struct statfs *, int);

static struct super_operations qnx4_sops =
{
	read_inode:		qnx4_read_inode,
#ifdef CONFIG_QNX4FS_RW
	write_inode:		qnx4_write_inode,
	put_inode:		qnx4_put_inode,
	delete_inode:		qnx4_delete_inode,
#endif
	put_super:		qnx4_put_super,
#ifdef CONFIG_QNX4FS_RW
	write_super:		qnx4_write_super,
#endif
	statfs:			qnx4_statfs,
	remount_fs:		qnx4_remount,
};

static int qnx4_remount(struct super_block *sb, int *flags, char *data)
{
	struct qnx4_sb_info *qs;

	qs = &sb->u.qnx4_sb;
	qs->Version = QNX4_VERSION;
	if (*flags & MS_RDONLY) {
		return 0;
	}
	mark_buffer_dirty(qs->sb_buf, 1);

	return 0;
}

struct buffer_head *qnx4_getblk(struct inode *inode, int nr,
				 int create)
{
	struct buffer_head *result = NULL;

	if ( nr >= 0 )
		nr = qnx4_block_map( inode, nr );
	if (nr) {
		result = getblk(inode->i_dev, nr, QNX4_BLOCK_SIZE);
		return result;
	}
	if (!create) {
		return NULL;
	}
#if 0
	tmp = qnx4_new_block(inode->i_sb);
	if (!tmp) {
		return NULL;
	}
	result = getblk(inode->i_dev, tmp, QNX4_BLOCK_SIZE);
	if (tst) {
		qnx4_free_block(inode->i_sb, tmp);
		brelse(result);
		goto repeat;
	}
	tst = tmp;
#endif
	inode->i_ctime = CURRENT_TIME;
	mark_inode_dirty(inode);
	return result;
}

struct buffer_head *qnx4_bread(struct inode *inode, int block, int create)
{
	struct buffer_head *bh;

	bh = qnx4_getblk(inode, block, create);
	if (!bh || buffer_uptodate(bh)) {
		return bh;
	}
	ll_rw_block(READ, 1, &bh);
	wait_on_buffer(bh);
	if (buffer_uptodate(bh)) {
		return bh;
	}
	brelse(bh);

	return NULL;
}

unsigned long qnx4_block_map( struct inode *inode, long iblock )
{
	int ix;
	long offset, i_xblk;
	unsigned long block = 0;
	struct buffer_head *bh = 0;
	struct qnx4_xblk *xblk = 0;
	struct qnx4_inode_info *qnx4_inode = &inode->u.qnx4_i;
	qnx4_nxtnt_t nxtnt = le16_to_cpu(qnx4_inode->i_num_xtnts);

	if ( iblock < le32_to_cpu(qnx4_inode->i_first_xtnt.xtnt_size) ) {
		// iblock is in the first extent. This is easy.
		block = le32_to_cpu(qnx4_inode->i_first_xtnt.xtnt_blk) + iblock - 1;
	} else {
		// iblock is beyond first extent. We have to follow the extent chain.
		i_xblk = le32_to_cpu(qnx4_inode->i_xblk);
		offset = iblock - le32_to_cpu(qnx4_inode->i_first_xtnt.xtnt_size);
		ix = 0;
		while ( --nxtnt > 0 ) {
			if ( ix == 0 ) {
				// read next xtnt block.
				bh = bread( inode->i_dev, i_xblk - 1, QNX4_BLOCK_SIZE );
				if ( !bh ) {
					QNX4DEBUG(("qnx4: I/O error reading xtnt block [%ld])\n", i_xblk - 1));
					return -EIO;
				}
				xblk = (struct qnx4_xblk*)bh->b_data;
				if ( memcmp( xblk->xblk_signature, "IamXblk", 7 ) ) {
					QNX4DEBUG(("qnx4: block at %ld is not a valid xtnt\n", qnx4_inode->i_xblk));
					return -EIO;
				}
			}
			if ( offset < le32_to_cpu(xblk->xblk_xtnts[ix].xtnt_size) ) {
				// got it!
				block = le32_to_cpu(xblk->xblk_xtnts[ix].xtnt_blk) + offset - 1;
				break;
			}
			offset -= le32_to_cpu(xblk->xblk_xtnts[ix].xtnt_size);
			if ( ++ix >= xblk->xblk_num_xtnts ) {
				i_xblk = le32_to_cpu(xblk->xblk_next_xblk);
				ix = 0;
				brelse( bh );
				bh = 0;
			}
		}
		if ( bh )
			brelse( bh );
	}

	QNX4DEBUG(("qnx4: mapping block %ld of inode %ld = %ld\n",iblock,inode->i_ino,block));
	return block;
}

static int qnx4_statfs(struct super_block *sb,
		       struct statfs *buf, int bufsize)
{
	struct statfs tmp;

	memset(&tmp, 0, sizeof tmp);
	tmp.f_type    = sb->s_magic;
	tmp.f_bsize   = sb->s_blocksize;
	tmp.f_blocks  = le32_to_cpu(sb->u.qnx4_sb.BitMap->di_size) * 8;
	tmp.f_bfree   = qnx4_count_free_blocks(sb);
	tmp.f_bavail  = tmp.f_bfree;
	tmp.f_files   = -1;	/* we don't count files */
	tmp.f_ffree   = -1;	/* inodes are allocated dynamically */
	tmp.f_namelen = QNX4_NAME_MAX;

	return copy_to_user(buf, &tmp, bufsize) ? -EFAULT : 0;
}

/*
 * Check the root directory of the filesystem to make sure
 * it really _is_ a qnx4 filesystem, and to check the size
 * of the directory entry.
 */
static const char *qnx4_checkroot(struct super_block *sb)
{
	struct buffer_head *bh;
	struct qnx4_inode_entry *rootdir;
	int rd, rl;
	int i, j;
	int found = 0;

	if (*(sb->u.qnx4_sb.sb->RootDir.di_fname) != '/') {
		return "no qnx4 filesystem (no root dir).";
	} else {
		QNX4DEBUG(("QNX4 filesystem found on dev %s.\n", kdevname(s->s_dev)));
		rd = le32_to_cpu(sb->u.qnx4_sb.sb->RootDir.di_first_xtnt.xtnt_blk) - 1;
		rl = le32_to_cpu(sb->u.qnx4_sb.sb->RootDir.di_first_xtnt.xtnt_size);
		for (j = 0; j < rl; j++) {
			bh = bread(sb->s_dev, rd + j, QNX4_BLOCK_SIZE);	/* root dir, first block */
			if (bh == NULL) {
				return "unable to read root entry.";
			}
			for (i = 0; i < QNX4_INODES_PER_BLOCK; i++) {
				rootdir = (struct qnx4_inode_entry *) (bh->b_data + i * QNX4_DIR_ENTRY_SIZE);
				if (rootdir->di_fname != NULL) {
					QNX4DEBUG(("Rootdir entry found : [%s]\n", rootdir->di_fname));
					if (!strncmp(rootdir->di_fname, QNX4_BMNAME, sizeof QNX4_BMNAME)) {
						found = 1;
						sb->u.qnx4_sb.BitMap = kmalloc( sizeof( struct qnx4_inode_entry ), GFP_KERNEL );
						memcpy( sb->u.qnx4_sb.BitMap, rootdir, sizeof( struct qnx4_inode_entry ) );	/* keep bitmap inode known */
						break;
					}
				}
			}
			brelse(bh);
			if (found != 0) {
				break;
			}
		}
		if (found == 0) {
			return "bitmap file not found.";
		}
	}
	return NULL;
}

static struct super_block *qnx4_read_super(struct super_block *s, 
					   void *data, int silent)
{
	struct buffer_head *bh;
	kdev_t dev = s->s_dev;
	struct inode *root;
	const char *errmsg;

	MOD_INC_USE_COUNT;
	lock_super(s);
	set_blocksize(dev, QNX4_BLOCK_SIZE);
	s->s_blocksize = QNX4_BLOCK_SIZE;
	s->s_blocksize_bits = QNX4_BLOCK_SIZE_BITS;
	s->s_dev = dev;

	/* Check the boot signature. Since the qnx4 code is
	   dangerous, we should leave as quickly as possible
	   if we don't belong here... */
	bh = bread(dev, 0, QNX4_BLOCK_SIZE);
	if (!bh) {
		printk("qnx4: unable to read the boot sector\n");
		goto outnobh;
	}
	if ( memcmp( (char*)bh->b_data + 4, "QNX4FS", 6 ) ) {
		if (!silent)
			printk("qnx4: wrong fsid in boot sector.\n");
		goto out;
	}
	brelse(bh);

	bh = bread(dev, 1, QNX4_BLOCK_SIZE);
	if (!bh) {
		printk("qnx4: unable to read the superblock\n");
		goto outnobh;
	}
	s->s_op = &qnx4_sops;
	s->s_magic = QNX4_SUPER_MAGIC;
#ifndef CONFIG_QNX4FS_RW
	s->s_flags |= MS_RDONLY;	/* Yup, read-only yet */
#endif
	s->u.qnx4_sb.sb_buf = bh;
	s->u.qnx4_sb.sb = (struct qnx4_super_block *) bh->b_data;

	/* check before allocating dentries, inodes, .. */
	errmsg = qnx4_checkroot(s);
	if (errmsg != NULL) {
		if (!silent)
			printk("qnx4: %s\n", errmsg);
		goto out;
	}

	/* does root not have inode number QNX4_ROOT_INO ?? */
	root = iget(s, QNX4_ROOT_INO * QNX4_INODES_PER_BLOCK);
	if (!root) {
		printk("qnx4: get inode failed\n");
		goto out;
	}

	s->s_root = d_alloc_root(root, NULL);
	if (s->s_root == NULL)
		goto outi;

	brelse(bh);
	unlock_super(s);
	s->s_dirt = 1;

	return s;

      outi:
	iput(root);
      out:
	brelse(bh);
      outnobh:
	s->s_dev = 0;
	unlock_super(s);
	MOD_DEC_USE_COUNT;

	return NULL;
}

static void qnx4_put_super(struct super_block *sb)
{
	kfree_s( sb->u.qnx4_sb.BitMap, sizeof( struct qnx4_inode_entry ) );
	MOD_DEC_USE_COUNT;
	return;
}

static void qnx4_read_inode(struct inode *inode)
{
	struct buffer_head *bh;
	struct qnx4_inode_entry *raw_inode;
	int block, ino;

	ino = inode->i_ino;
	inode->i_op = NULL;
	inode->i_mode = 0;

	QNX4DEBUG(("Reading inode : [%d]\n", ino));
	if (!ino) {
		printk("qnx4: bad inode number on dev %s: %d is out of range\n",
		       kdevname(inode->i_dev), ino);
		return;
	}
	block = ino / QNX4_INODES_PER_BLOCK;

	if (!(bh = bread(inode->i_dev, block, QNX4_BLOCK_SIZE))) {
		printk("qnx4: major problem: unable to read inode from dev "
		       "%s\n", kdevname(inode->i_dev));
		return;
	}
	raw_inode = ((struct qnx4_inode_entry *) bh->b_data) +
	    (ino % QNX4_INODES_PER_BLOCK);

	inode->i_mode    = le16_to_cpu(raw_inode->di_mode);
	inode->i_uid     = le16_to_cpu(raw_inode->di_uid);
	inode->i_gid     = le16_to_cpu(raw_inode->di_gid);
	inode->i_nlink   = le16_to_cpu(raw_inode->di_nlink);
	inode->i_size    = le32_to_cpu(raw_inode->di_size);
	inode->i_mtime   = le32_to_cpu(raw_inode->di_mtime);
	inode->i_atime   = le32_to_cpu(raw_inode->di_atime);
	inode->i_ctime   = le32_to_cpu(raw_inode->di_ctime);
	inode->i_blocks  = le32_to_cpu(raw_inode->di_first_xtnt.xtnt_size);
	inode->i_blksize = QNX4_DIR_ENTRY_SIZE;

	memcpy(&inode->u.qnx4_i, (struct qnx4_inode_info *) raw_inode, QNX4_DIR_ENTRY_SIZE);
	inode->i_op = &qnx4_file_inode_operations;
	if (S_ISREG(inode->i_mode))
		inode->i_op = &qnx4_file_inode_operations;
	else if (S_ISDIR(inode->i_mode))
		inode->i_op = &qnx4_dir_inode_operations;
	else if (S_ISLNK(inode->i_mode))
		inode->i_op = &qnx4_symlink_inode_operations;
	else
		printk("qnx4: bad inode %d on dev %s\n",ino,kdevname(inode->i_dev));
	brelse(bh);
}

static struct file_system_type qnx4_fs_type =
{
	"qnx4",
	FS_REQUIRES_DEV,
	qnx4_read_super,
	NULL
};

__initfunc(int init_qnx4_fs(void))
{
	printk("QNX4 filesystem v0.2.2 registered.\n");
	return register_filesystem(&qnx4_fs_type);
}

#ifdef MODULE
EXPORT_NO_SYMBOLS;

int init_module(void)
{
	return init_qnx4_fs();
}

void cleanup_module(void)
{
	unregister_filesystem(&qnx4_fs_type);
}

#endif
