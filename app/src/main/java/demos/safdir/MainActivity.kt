package demos.safdir

import android.os.Bundle
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.documentfile.provider.DocumentFile
import androidx.recyclerview.widget.LinearLayoutManager
import demos.safdir.databinding.ActivityMainBinding
import java.util.ArrayDeque

/**
 * 选择目录（SAF）→ 列出当前目录的直接子项 → 点目录进入子层 → 文件旁删除并确认。
 */
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var adapter: BrowseListAdapter

    /** 已授权目录树的 documentId 根；导航栈从根到当前目录。 */
    private val dirStack: ArrayDeque<DocumentFile> = ArrayDeque()

    private val openTree = registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri == null) {
            toast(getString(R.string.status_none))
            return@registerForActivityResult
        }
        contentResolver.takePersistableUriPermission(
            uri,
            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        val root = DocumentFile.fromTreeUri(this, uri) ?: run {
            toast("无法打开该目录")
            return@registerForActivityResult
        }
        dirStack.clear()
        dirStack.addLast(root)
        refreshList()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        adapter = BrowseListAdapter(
            onOpenDir = { d -> openChildDir(d) },
            onDeleteFile = { f -> confirmDelete(f) },
        )
        binding.recycler.layoutManager = LinearLayoutManager(this)
        binding.recycler.adapter = adapter

        binding.tvStatus.text = getString(R.string.status_none)

        binding.btnPick.setOnClickListener { openTree.launch(null) }
        binding.btnRefresh.setOnClickListener {
            if (dirStack.isEmpty()) toast("请先选择目录")
            else refreshList()
        }
        binding.btnUp.setOnClickListener { goUp() }
    }

    private fun currentDir(): DocumentFile? = dirStack.lastOrNull()

    private fun openChildDir(entry: BrowseEntry.Dir) {
        dirStack.addLast(entry.doc)
        refreshList()
    }

    private fun goUp() {
        if (dirStack.size <= 1) {
            toast("已在根目录")
            return
        }
        dirStack.removeLast()
        refreshList()
    }

    private fun refreshList() {
        val dir = currentDir() ?: run {
            binding.tvStatus.text = getString(R.string.status_none)
            adapter.replaceAll(emptyList())
            return
        }

        val raw = dir.listFiles()
        val entries = raw.mapNotNull { f ->
            val n = f.name ?: return@mapNotNull null
            when {
                f.isDirectory -> BrowseEntry.Dir(n, f)
                f.isFile -> BrowseEntry.FileItem(n, f)
                else -> null
            }
        }.sortedWith(
            compareBy<BrowseEntry> { it is BrowseEntry.FileItem }
                .thenBy { it.name.lowercase() },
        )

        adapter.replaceAll(entries)

        val depth = dirStack.size
        val title = dir.name ?: dir.uri.toString()
        binding.tvStatus.text = buildString {
            append("当前层级: ").append(depth).append('\n')
            append("文件夹: ").append(title).append('\n')
            append("本层条目数: ").append(entries.size)
        }
    }

    private fun confirmDelete(file: BrowseEntry.FileItem) {
        AlertDialog.Builder(this)
            .setTitle(R.string.delete_confirm_title)
            .setMessage(getString(R.string.delete_confirm_message, file.name))
            .setNegativeButton(R.string.delete_confirm_negative, null)
            .setPositiveButton(R.string.delete_confirm_positive) { _, _ ->
                if (file.doc.delete()) {
                    toast(getString(R.string.toast_delete_ok))
                    refreshList()
                } else {
                    toast(getString(R.string.toast_delete_fail))
                }
            }
            .show()
    }

    private fun toast(msg: String) {
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
    }
}
