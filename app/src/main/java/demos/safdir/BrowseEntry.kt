package demos.safdir

import androidx.documentfile.provider.DocumentFile

/** 当前目录下列出的单条条目：子目录（可点入）或文件（可删除）。 */
sealed class BrowseEntry {
    abstract val name: String

    data class Dir(
        override val name: String,
        val doc: DocumentFile,
    ) : BrowseEntry()

    data class FileItem(
        override val name: String,
        val doc: DocumentFile,
    ) : BrowseEntry()
}
